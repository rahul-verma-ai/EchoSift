import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vibration/vibration.dart';

import 'bloc/vent_bloc.dart';
import 'repository/api_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EchoSiftApp());
}

class EchoSiftApp extends StatelessWidget {
  const EchoSiftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EchoSift',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: RepositoryProvider(
        create: (_) => ApiRepository(),
        child: BlocProvider(
          create: (context) => VentBloc(context.read<ApiRepository>()),
          child: const VentPage(),
        ),
      ),
    );
  }
}

class VentPage extends StatefulWidget {
  const VentPage({super.key});

  @override
  State<VentPage> createState() => _VentPageState();
}

class _VentPageState extends State<VentPage> {
  final List<Color> _warpColors = [
    const Color(0xFF1A1A1D),
    const Color(0xFF0D1B2A),
    const Color(0xFF2D0B0B),
    const Color(0xFF1B1B1B),
  ];

  int _currentColorIndex = 0;
  Timer? _pulseTimer;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _startGlobalGroundingPulse();
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    super.dispose();
  }

  void _startGlobalGroundingPulse() {
    final int nextInterval = 3 + _random.nextInt(4);

    _pulseTimer = Timer(Duration(seconds: nextInterval), () async {
      if (mounted) {
        // Fix 2: Simplified the null-aware check
        if (await Vibration.hasVibrator() == true) {
          Vibration.vibrate(duration: 50, amplitude: 128);
        }
        _startGlobalGroundingPulse();
      }
    });
  }

  void _onVentPressed(BuildContext context, VentState state) {
    if (state is VentProcessing) return;

    Vibration.vibrate(duration: 80, amplitude: 255);

    final bloc = context.read<VentBloc>();

    if (state is VentRecording) {
      bloc.add(VentStopRequested());
    } else {
      bloc.add(VentStartRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<VentBloc, VentState>(
      listener: (context, state) {
        if (state is VentFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
        if (state is VentCompleted) {
          Vibration.vibrate(pattern: [0, 100, 50, 100]);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: TweenAnimationBuilder<Color?>(
          duration: const Duration(seconds: 8),
          tween: ColorTween(
            begin: _warpColors[_currentColorIndex],
            end: _warpColors[(_currentColorIndex + 1) % _warpColors.length],
          ),
          onEnd: () {
            setState(() {
              _currentColorIndex =
                  (_currentColorIndex + 1) % _warpColors.length;
            });
          },
          builder: (context, color, child) {
            return AnimatedContainer(
              duration: const Duration(seconds: 8),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.4,
                  colors: [
                    color ?? _warpColors[0],
                    Colors.black,
                  ],
                ),
              ),
              child: child,
            );
          },
          child: SafeArea(
            child: Center(
              child: BlocBuilder<VentBloc, VentState>(
                builder: (context, state) {
                  if (state is VentCompleted) {
                    return _buildResultView(context, state.response);
                  }

                  if (state is VentProcessing) {
                    return _buildProcessingView();
                  }

                  final bool isRecording = state is VentRecording;

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => _onVentPressed(context, state),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: isRecording ? 160 : 120,
                          height: isRecording ? 160 : 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            // Fix 3: Using .withValues instead of .withOpacity
                            color: isRecording
                                ? Colors.redAccent.withValues(alpha: 0.8)
                                : Colors.white.withValues(alpha: 0.05),
                            border: Border.all(
                              color:
                                  isRecording ? Colors.white38 : Colors.white12,
                              width: 2,
                            ),
                            boxShadow: [
                              if (isRecording)
                                BoxShadow(
                                  color:
                                      Colors.redAccent.withValues(alpha: 0.2),
                                  blurRadius: 40,
                                  spreadRadius: 20,
                                ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            isRecording ? 'STOP' : 'VENT',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              letterSpacing: 4,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      if (isRecording)
                        const Text(
                          "Listening...",
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 14,
                            letterSpacing: 1.5,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultView(BuildContext context, String response) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome, color: Colors.white24, size: 40),
          const SizedBox(height: 30),
          Text(
            response,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              height: 1.6,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 60),
          OutlinedButton(
            onPressed: () {
              Vibration.vibrate(duration: 50);
              context.read<VentBloc>().add(VentResetRequested());
            },
            style: OutlinedButton.styleFrom(
              // Fix 4: Using BorderSide instead of Border.all
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text(
              "VENT AGAIN",
              style: TextStyle(
                color: Colors.white70,
                letterSpacing: 2,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            color: Colors.white12,
            strokeWidth: 2,
          ),
        ),
        const SizedBox(height: 40),
        Text(
          "Sifting through the echoes of your emotions...",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontStyle: FontStyle.italic,
            fontSize: 15,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }
}
