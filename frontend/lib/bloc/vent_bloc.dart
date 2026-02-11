import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../repository/api_repository.dart';

part 'vent_event.dart';
part 'vent_state.dart';

class VentBloc extends Bloc<VentEvent, VentState> {
  final ApiRepository _repository;
  final AudioRecorder _recorder = AudioRecorder();

  String? _currentFilePath;
  String? _sessionId;

  VentBloc(this._repository) : super(VentInitial()) {
    on<VentStartRequested>(_onStart);
    on<VentStopRequested>(_onStop);
    on<VentResetRequested>((event, emit) => emit(VentInitial()));
  }

  Future<void> _onStart(
    VentStartRequested event,
    Emitter<VentState> emit,
  ) async {
    // IDEMPOTENCY GUARD: Don't start if already active
    if (state is VentRecording || state is VentProcessing) return;
    try {
      final permission = await Permission.microphone.request();
      if (!permission.isGranted) {
        emit(VentFailure('Microphone permission denied'));
        return;
      }

      _sessionId ??= await _repository.createSession();

      // Ensure unique filename using milliseconds to avoid OS-level file caching/ghosting
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentFilePath = '${appDir.path}/vent_$timestamp.m4a';

      print('STARTING RECORDING AT: $_currentFilePath');

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 16000, // Optimized for OpenAI Whisper
          numChannels: 1, // Mono reduces file size further
        ),
        path: _currentFilePath!,
      );

      emit(VentRecording());
    } catch (e) {
      print('ERROR STARTING RECORDING: $e');
      emit(VentFailure('Failed to start recording'));
    }
  }

  Future<void> _onStop(
    VentStopRequested event,
    Emitter<VentState> emit,
  ) async {
    // IDEMPOTENCY GUARD: Only stop if we are actually recording
    if (state is! VentRecording) return;
    try {
      print('--- STOPPING RECORDER ---');
      final path = await _recorder.stop();

      // Update path in case the recorder package modified it during finalization
      if (path != null) {
        _currentFilePath = path;
      }

      if (_currentFilePath == null || _sessionId == null) {
        emit(VentFailure('Invalid recording session'));
        return;
      }

      final file = File(_currentFilePath!);
      if (!await file.exists()) {
        emit(VentFailure('Recording file not found.'));
        return;
      }

      print('FILE SAVED AT: $_currentFilePath (${await file.length()} bytes)');
      emit(VentProcessing());

      print('STARTING UPLOAD TO BACKEND...');
      final response = await _repository.uploadVent(
        sessionId: _sessionId!,
        audioFile: file,
      );

      print('--- SERVER DATA RECEIVED ---');
      emit(VentCompleted(response));
    } on SessionExpiredException {
      _resetSession();
      emit(VentSessionExpired());
    } on TimeoutException {
      emit(VentFailure(
          'The AI is sifting through your words. Please try again in a moment.'));
    } catch (e, stackTrace) {
      print('CRITICAL ERROR: $e\n$stackTrace');
      emit(VentFailure('Something went wrong. Please try again.'));
    } finally {
      // Logic for ephemeral data management
      await _deleteLocalFile();
      _cleanup();
    }
  }

  /// Deletes the local recording file to free up space and maintain privacy
  Future<void> _deleteLocalFile() async {
    if (_currentFilePath != null) {
      try {
        final file = File(_currentFilePath!);
        if (await file.exists()) {
          await file.delete();
          print('EPHEMERAL CLEANUP: Local file deleted successfully.');
        }
      } catch (e) {
        print('CLEANUP ERROR: Could not delete file: $e');
      }
    }
  }

  void _cleanup() {
    _currentFilePath = null;
  }

  void _resetSession() {
    _sessionId = null;
  }

  @override
  Future<void> close() async {
    await _recorder.dispose();
    return super.close();
  }
}
