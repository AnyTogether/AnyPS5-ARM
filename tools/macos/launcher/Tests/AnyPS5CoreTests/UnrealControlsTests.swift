import XCTest
@testable import AnyPS5Core

final class UnrealControlsTests: XCTestCase {
    let input = """
    [/Script/Engine.InputSettings]
    bAltEnterTogglesFullscreen=True
    +ActionMappings=(ActionName="Jump",bShift=False,bCtrl=False,bAlt=False,bCmd=False,Key=Gamepad_FaceButton_Bottom)
    +ActionMappings=(ActionName="Jump",bShift=False,bCtrl=False,bAlt=False,bCmd=False,Key=SpaceBar)
    +ActionMappings=(ActionName="Interact_Primary",Key=Gamepad_FaceButton_Left)
    +ActionMappings=(ActionName="IA_Meow",Key=Gamepad_RightShoulder)
    +ActionMappings=(ActionName="OpenMenu",Key=Gamepad_Special_Right)
    +AxisMappings=(AxisName="MoveForward",Scale=1.000000,Key=Gamepad_LeftY)
    +AxisMappings=(AxisName="MoveRight",Scale=-1.000000,Key=Gamepad_LeftX)
    +AxisMappings=(AxisName="Sprint",Scale=1.000000,Key=Gamepad_RightTriggerAxis)
    +AxisMappings=(AxisName="LookUp",Scale=1.000000,Key=Gamepad_RightY)
    """

    func testEachButtonSaysWhatTheGameDoesWithIt() {
        let controls = UnrealControls.parse([input])
        XCTAssertEqual(controls[.cross], ["Jump"])
        XCTAssertEqual(controls[.square], ["Interact primary"])
        XCTAssertEqual(controls[.r1], ["Meow"])
        XCTAssertEqual(controls[.options], ["Open menu"])
        XCTAssertEqual(controls[.r2], ["Sprint"])
        XCTAssertEqual(controls[.leftStickUp], ["Move forward"])
        XCTAssertEqual(controls[.leftStickDown], ["Move forward"])
        XCTAssertEqual(controls[.leftStickLeft], ["Move right"])
        XCTAssertEqual(controls[.rightStickUp], ["Look up"])
        XCTAssertNil(controls[.circle])
    }

    /// A later file adds to, takes from or clears what the earlier said, as Unreal's ini layers do.
    func testLaterFilesChangeTheEarlierOnes() {
        let platform = """
        [/Script/Engine.InputSettings]
        -ActionMappings=(ActionName="Interact_Primary",Key=Gamepad_FaceButton_Left)
        +ActionMappings=(ActionName="Interact_Primary",Key=Gamepad_FaceButton_Right)
        """
        let controls = UnrealControls.parse([input, platform])
        XCTAssertNil(controls[.square])
        XCTAssertEqual(controls[.circle], ["Interact primary"])
        let cleared = UnrealControls.parse([input, "[/Script/Engine.InputSettings]\n!ActionMappings=ClearArray\n"])
        XCTAssertNil(cleared[.cross])
        XCTAssertEqual(cleared[.r2], ["Sprint"], "axes stay")
    }

    func testOtherSectionsAreLeftAlone() {
        let controls = UnrealControls.parse(["[/Script/Other.Thing]\n+ActionMappings=(ActionName=\"Jump\",Key=Gamepad_FaceButton_Bottom)\n"])
        XCTAssertTrue(controls.isEmpty)
    }

    /// The game's own input file, found in a pak in the game's folder.
    func testTheControlsAreReadFromTheGamesPak() throws {
        let game = FileManager.default.temporaryDirectory.appendingPathComponent("game-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: game) }
        let paks = game.appendingPathComponent("Stray/Content/Paks")
        try FileManager.default.createDirectory(at: paks, withIntermediateDirectories: true)
        try PakWriter(version: 11, files: [
            ("Engine/Config/BaseInput.ini", Data("[/Script/Engine.InputSettings]\n+ActionMappings=(ActionName=\"EngineThing\",Key=Gamepad_FaceButton_Top)\n".utf8), false),
            ("Stray/Config/DefaultInput.ini", Data(input.utf8), true),
        ]).write(to: paks.appendingPathComponent("pakchunk0-ps5.pak"))
        let controls = try XCTUnwrap(UnrealControls.read(game: game))
        XCTAssertEqual(controls[.cross], ["Jump"])
        XCTAssertNil(controls[.triangle], "the engine's own file says nothing of the game")
    }

    func testAGameWithoutPaksHasNone() throws {
        XCTAssertNil(UnrealControls.read(game: FileManager.default.temporaryDirectory.appendingPathComponent("nothing-\(UUID().uuidString)")))
    }
}
