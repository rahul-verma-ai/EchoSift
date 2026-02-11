part of 'vent_bloc.dart';

abstract class VentState extends Equatable {
  @override
  List<Object?> get props => [];
}

class VentInitial extends VentState {}

class VentRecording extends VentState {}

class VentProcessing extends VentState {}

class VentCompleted extends VentState {
  final String response;
  VentCompleted(this.response);

  @override
  List<Object?> get props => [response];
}

class VentSessionExpired extends VentState {}

class VentFailure extends VentState {
  final String message;
  VentFailure(this.message);

  @override
  List<Object?> get props => [message];
}
