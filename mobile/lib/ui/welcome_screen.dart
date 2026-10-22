import 'package:flutter/material.dart';

import '../strings.dart';

/// The first start: what the app is, and the one button that begins the setup.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final texts = Texts.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF07080B),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.sports_esports_rounded,
                  color: Colors.white,
                  size: 52,
                ),
                const SizedBox(height: 18),
                Text(
                  texts.welcomeTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  texts.welcomeText,
                  style: const TextStyle(color: Colors.white60, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 26),
                Wrap(
                  spacing: 28,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    _Step(number: 1, text: texts.stepOpen),
                    _Step(number: 2, text: texts.stepWifi),
                    _Step(number: 3, text: texts.stepAllow),
                  ],
                ),
                const SizedBox(height: 30),
                FilledButton(
                  onPressed: onStart,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 44,
                      vertical: 16,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(texts.start),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x55FFFFFF)),
        ),
        child: Text(
          '$number',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Text(text, style: const TextStyle(color: Colors.white, fontSize: 15)),
    ],
  );
}
