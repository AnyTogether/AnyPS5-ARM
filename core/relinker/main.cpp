#include <ConsoleProgress.hpp>
#include <RuntimeLayout.hpp>
#include <NativeModules.hpp>
#include <relinker/pipeline/Conversion.hpp>
#include <Cli.hpp>
#include <domain/Types.hpp>
#include <io/FileReader.hpp>
#include <io/NativePath.hpp>
#include <elfpatcher/linux/LinuxDesktopEntryWriter.hpp>
#include <io/FileWriter.hpp>
#include <relinker/output/CallRegistryWriter.hpp>
#include <codegen/CodegenException.hpp>
#include <algorithm>
#include <filesystem>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#include <cwchar>
#endif

namespace {

struct ConvertedExecutable {
    std::string InputPath;
    std::string OutputPath;
    Relinker::RelinkResult Result;
    std::vector<Relinker::GuestArtifact> GuestArtifacts;
    std::vector<std::uint8_t> Bytes;
    std::string Diagnostics;
};

ConvertedExecutable Convert(const Cli::Args& args, const std::string& inputPath, const std::string& absPath, const bool mainExecutable, Cli::ConsoleProgress& progress) {
    Io::FileReader fileReader;
    Relinker::ConversionInput input;
    input.Executable = fileReader.Read(inputPath);
    input.InputPath = std::filesystem::absolute(Io::NativePath(inputPath)).lexically_normal();
    input.OutputPath = Io::NativePath(absPath);
    if (!args.skipSceModule) {
        auto modules = Cli::ReadModules(input.InputPath, Io::NativePath(args.sceModulePath), args.excludedSceModules, args.moduleDirectories);
        input.ModuleRoot = std::move(modules.Root);
        input.Modules = std::move(modules.Modules);
        input.RuntimeDirectories = std::move(modules.RuntimeDirectories);
    }
    const auto iconPath = Io::NativePath(args.inputPath).parent_path() / "sce_sys" / "icon0.png";
    if (args.toWindows && std::filesystem::exists(iconPath)) input.Icon = fileReader.Read(Io::Utf8Path(iconPath));
    Relinker::ConversionOptions options;
    options.Target = args.toWindows ? Relinker::TargetSystem::Windows : args.toMacos ? Relinker::TargetSystem::MacOs : Relinker::TargetSystem::Linux;
    options.ToIntel = args.toIntel;
    options.ToRosetta = args.toRosetta;
    options.SkipSyscallCheck = args.skipSyscallCheck;
    options.TrapSdkSyscallStubs = args.trapSdkSyscallStubs;
    options.UnusedFilterLevel = args.unusedFilterLevel;
    options.LazyBinding = args.lazyBinding;
    options.RunPath = args.runPath;
    options.WindowsGui = args.windowsGui;
    options.TraceImports = args.traceImports;
    options.WindowsFixedBase = mainExecutable ? args.windowsFixedBase : std::nullopt;
    options.WindowsDiagnostics = args.windowsDiagnostics && mainExecutable;
    options.ExcludedModules = args.excludedSceModules;
    progress.IncludeFile(Io::Utf8Path(input.InputPath));
    progress.IncludeFile(Io::Utf8Path(input.OutputPath));
    for (const auto& module : input.Modules) progress.IncludeFile(Io::Utf8Path(module.Path));
    auto converted = Relinker::Conversion(progress).Convert(std::move(input), options);
    return {inputPath, absPath, std::move(converted.Analysis), std::move(converted.Modules), std::move(converted.Executable), std::move(converted.WindowsDiagnostics)};
}

int Run(const int argc, char* argv[]) {
    Cli::Args args;
    try {
        args = Cli::ParseArgs(argc, argv);
    } catch (const std::exception& e) {
        std::cerr << "FAIL: " << e.what() << "\n";
        return 1;
    }

    if (args.showHelp) {
        std::cout << Cli::Usage() << '\n';
        return 0;
    }

    Cli::ConsoleProgress progress(std::cout);
    try {
        auto extension = Io::Utf8Path(Io::NativePath(args.outputPath).extension());
        for (auto& character : extension) if (character >= 'A' && character <= 'Z') character = static_cast<char>(character + ('a' - 'A'));
        if (!args.toWindows && !args.toMacos && extension == ".exe") std::cerr << "WARNING: Output filename ends with .exe, but --windows was not specified. The output will be a Linux ELF executable.\n";
        Io::FileWriter fileWriter;

        if (std::filesystem::exists(Io::NativePath(args.inputPath)) && std::filesystem::exists(Io::NativePath(args.outputPath)) && std::filesystem::equivalent(Io::NativePath(args.inputPath), Io::NativePath(args.outputPath)))
            throw Domain::RelinkerException("Executable output would overwrite the input executable");
        if (Io::NativePath(args.outputPath).filename().empty() || std::filesystem::is_directory(Io::NativePath(args.outputPath)))
            throw Domain::RelinkerException("Executable output is a directory: " + args.outputPath);
        const std::string absPath = Io::Utf8Path(std::filesystem::absolute(Io::NativePath(args.outputPath)));

        struct ExtraExecutable {
            std::string Argument;
            std::filesystem::path Relative;
            std::filesystem::path Input;
            std::filesystem::path Output;
        };
        std::vector<ExtraExecutable> extraExecutables;
        const auto outputDirectory = Io::NativePath(absPath).parent_path();
        const auto moduleRoot = args.executables.empty() ? std::filesystem::path() : std::filesystem::absolute(Io::NativePath(args.sceModulePath)).lexically_normal();
        std::vector<std::filesystem::path> moduleDirectories;
        for (const auto* name : {"sce_module", "sce_modules", "prx"}) moduleDirectories.push_back(moduleRoot / name);
        for (const auto& name : args.moduleDirectories) moduleDirectories.push_back((moduleRoot / Io::NativePath(name)).lexically_normal());
        for (auto& directory : moduleDirectories) if (!directory.has_filename()) directory = directory.parent_path();
        for (const auto& executable : args.executables) {
            const auto relative = Io::NativePath(executable).lexically_normal();
            if (relative.empty() || relative.has_root_path() || *relative.begin() == ".." || !relative.has_filename())
                throw Domain::RelinkerException("--executable must be a file inside the guest module parent directory: " + executable);
            const auto input = moduleRoot / relative;
            if (!std::filesystem::is_regular_file(input)) throw Domain::RelinkerException("--executable is not a file: " + Io::Utf8Path(input));
            if (std::find(moduleDirectories.begin(), moduleDirectories.end(), input.parent_path()) != moduleDirectories.end())
                throw Domain::RelinkerException("--executable is in a guest module directory: " + executable);
            std::string name;
            for (const auto& part : relative) name += (name.empty() ? "" : ".") + Io::Utf8Path(part);
            const auto output = outputDirectory / Io::NativePath(name + Io::Utf8Path(Io::NativePath(absPath).extension()));
            if (std::filesystem::equivalent(Io::NativePath(args.inputPath), input)) throw Domain::RelinkerException("Executable is converted twice: " + executable);
            if (output.lexically_normal() == Io::NativePath(absPath).lexically_normal()) throw Domain::RelinkerException("Executable outputs collide: " + Io::Utf8Path(output));
            for (const auto& extra : extraExecutables) {
                if (std::filesystem::equivalent(extra.Input, input)) throw Domain::RelinkerException("Executable is converted twice: " + executable);
                if (extra.Output.lexically_normal() == output.lexically_normal()) throw Domain::RelinkerException("Executable outputs collide: " + Io::Utf8Path(output));
            }
            extraExecutables.push_back({executable, relative, input, output});
        }

        progress.IncludeFile(args.inputPath);
        progress.IncludeFile(absPath);
        for (const auto& extra : extraExecutables) {
            progress.IncludeFile(Io::Utf8Path(extra.Input));
            progress.IncludeFile(Io::Utf8Path(extra.Output));
        }
        std::vector<ConvertedExecutable> executables;
        executables.push_back(Convert(args, args.inputPath, absPath, true, progress));
        for (const auto& [executable, relative, input, output] : extraExecutables) {
            std::cout << "Executable: " << relative.generic_string() << '\n';
            auto converted = Convert(args, Io::Utf8Path(input), Io::Utf8Path(output), false, progress);
            const auto& mainArtifacts = executables.front().GuestArtifacts;
            const bool shared = converted.GuestArtifacts.size() == mainArtifacts.size() && std::equal(mainArtifacts.begin(), mainArtifacts.end(), converted.GuestArtifacts.begin(), [](const auto& left, const auto& right) {
                return left.Path == right.Path && left.Bytes == right.Bytes;
            });
            if (!shared) throw Domain::RelinkerException("Guest modules convert differently for " + executable + ", so it cannot share them with the input executable");
            executables.push_back(std::move(converted));
        }
        const auto& guestArtifacts = executables.front().GuestArtifacts;

        const Elfpatcher::Linux::LinuxDesktopEntryWriter desktopEntryWriter;
        const auto desktopEntry = args.toWindows || args.toMacos ? std::nullopt : desktopEntryWriter.Prepare(Io::NativePath(args.inputPath).parent_path() / "sce_sys", Io::NativePath(absPath));

        const auto checkOutputInputs = [&](const std::filesystem::path& path, const char* kind) {
            if (!std::filesystem::exists(path)) return;
            for (const auto& executable : executables)
                if (std::filesystem::equivalent(Io::NativePath(executable.InputPath), path))
                    throw Domain::RelinkerException(std::string(kind) + " output would overwrite the input executable: " + Io::Utf8Path(path));
            for (const auto& artifact : guestArtifacts)
                if (std::filesystem::equivalent(artifact.SourcePath, path))
                    throw Domain::RelinkerException(std::string(kind) + " output would overwrite an input module: " + Io::Utf8Path(path));
        };
        for (std::size_t index = 1; index < executables.size(); ++index) checkOutputInputs(Io::NativePath(executables[index].OutputPath), "Executable");
        if (desktopEntry) {
            checkOutputInputs(desktopEntry->IconPath, "Icon");
            checkOutputInputs(desktopEntry->EntryPath, "Desktop entry");
        }
        if (args.windowsDiagnostics)
            checkOutputInputs(std::filesystem::absolute("windows-diagnostics-imports.txt"), "Windows import diagnostics");

        std::vector<std::filesystem::path> registryPaths;
        if (args.writeRegistry) {
            for (const auto& executable : executables) {
                const std::filesystem::path outFsPath = Io::NativePath(executable.OutputPath);
                registryPaths.push_back(outFsPath.parent_path() / Io::NativePath(Io::Utf8Path(outFsPath.stem()) + ".registry.json"));
            }
            const std::filesystem::path outFsPath = Io::NativePath(absPath);
            for (const auto& artifact : guestArtifacts)
                registryPaths.push_back(outFsPath.parent_path() / Io::NativePath(Io::Utf8Path(outFsPath.stem()) + "." + Io::Utf8Path(artifact.Path.filename()) + ".registry.json"));
            for (const auto& path : registryPaths) checkOutputInputs(path, "Registry");
        }

        checkOutputInputs(Io::NativePath(absPath), "Executable");
        for (const auto& artifact : guestArtifacts) checkOutputInputs(artifact.Path, "Guest module");

        if (args.windowsDiagnostics) fileWriter.Write("windows-diagnostics-imports.txt", executables.front().Diagnostics);
        const auto outputCount = guestArtifacts.size() + executables.size();
        progress.Report({Domain::ProgressStage::Write, absPath, 0, outputCount});
        std::size_t written = 0;
        for (const auto& artifact : guestArtifacts) {
            std::filesystem::create_directories(artifact.Path.parent_path());
            fileWriter.Write(Io::Utf8Path(artifact.Path), artifact.Bytes);
            progress.Report({Domain::ProgressStage::Write, absPath, ++written, outputCount});
        }
        for (const auto& executable : executables) {
            fileWriter.Write(executable.OutputPath, executable.Bytes);
            progress.Report({Domain::ProgressStage::Write, absPath, ++written, outputCount});
        }
        if (args.writeRegistry) {
            const auto registryWriter = std::make_shared<Relinker::CallRegistryWriter>();
            for (std::size_t index = 0; index < executables.size(); ++index)
                fileWriter.Write(Io::Utf8Path(registryPaths[index]), registryWriter->WriteCallRegistry(executables[index].Result.RegistryEntries));
            for (std::size_t index = 0; index < guestArtifacts.size(); ++index)
                fileWriter.Write(Io::Utf8Path(registryPaths[executables.size() + index]), registryWriter->WriteModuleImports(guestArtifacts[index].Imports));
        }
        progress.Finish();
        if (desktopEntry) std::cout << "Desktop entry: " << Io::Utf8Path(desktopEntryWriter.Write(*desktopEntry)) << '\n';
        std::cout << "\nConversion complete\n"
                  << "Output file: " << absPath << '\n'
                  << "External prx references: " << executables.front().Result.RegistryEntries.size() << '\n'
                  << "Converted modules: " << guestArtifacts.size() << "\n\n";
        std::vector<std::string> extraPaths;
        for (std::size_t index = 1; index < executables.size(); ++index) {
            std::cout << "Executable file: " << executables[index].OutputPath << '\n';
            extraPaths.push_back(Io::Utf8Path(Io::NativePath(executables[index].OutputPath).filename()));
        }
        std::vector<std::string> modulePaths;
        for (const auto& artifact : guestArtifacts) {
            std::string relative = Io::Utf8Path(artifact.Path.lexically_relative(Io::NativePath(absPath).parent_path() / "app0"));
            std::replace(relative.begin(), relative.end(), '\\', '/');
            modulePaths.push_back(std::move(relative));
        }
        Cli::RuntimeLayout::Print(std::cout, Io::Utf8Path(Io::NativePath(absPath).filename()), modulePaths, extraPaths);
        if (args.runPath != "$ORIGIN/libs") std::cout << "Custom library search path (--rpath): " << args.runPath << '\n';

        if (args.autorun) return Cli::Autorun(absPath, args.toWindows);

    } catch (const Domain::RelinkerException& e) {
        progress.Finish();
        std::cerr << "FAIL: " << e.what();
        if (e.FailureOffset != 0) std::cerr << " (offset 0x" << std::hex << e.FailureOffset << ")";
        std::cerr << "\n";
        if (!e.InputPath.empty()) std::cerr << "Input: " << e.InputPath << '\n';
        return 2;
    } catch (const Codegen::CodegenException& e) {
        progress.Finish();
        std::cerr << "FAIL: " << e.what();
        if (e.FailureOffset != 0) std::cerr << " (offset 0x" << std::hex << e.FailureOffset << ")";
        std::cerr << "\n";
        return 2;
    } catch (const std::exception& e) {
        progress.Finish();
        std::cerr << "FAIL: " << e.what() << "\n";
        return 2;
    }

    return 0;
}

#ifdef _WIN32

std::string Utf8Argument(const wchar_t* argument) {
    const std::size_t argumentSize = std::wcslen(argument);
    if (argumentSize == 0) return {};
    const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, argument, static_cast<int>(argumentSize), nullptr, 0, nullptr, nullptr);
    if (size <= 0) throw std::runtime_error("Cannot encode the command line as UTF-8");
    std::string utf8(static_cast<std::size_t>(size), '\0');
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, argument, static_cast<int>(argumentSize), utf8.data(), size, nullptr, nullptr) != size)
        throw std::runtime_error("Cannot encode the command line as UTF-8");
    return utf8;
}

}

int wmain(const int argc, wchar_t* argv[]) {
    try {
        std::vector<std::string> arguments;
        arguments.reserve(static_cast<std::size_t>(argc));
        arguments.emplace_back();
        for (int index = 1; index < argc; ++index) arguments.push_back(Utf8Argument(argv[index]));
        std::vector<char*> pointers;
        pointers.reserve(arguments.size() + 1);
        for (auto& argument : arguments) pointers.push_back(argument.data());
        pointers.push_back(nullptr);
        return Run(static_cast<int>(arguments.size()), pointers.data());
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << "\n";
        return 1;
    }
}

#else

}

int main(const int argc, char* argv[]) {
    return Run(argc, argv);
}

#endif
