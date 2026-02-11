part of 'vent_bloc.dart';

abstract class VentEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class VentStartRequested extends VentEvent {}

class VentStopRequested extends VentEvent {}

class VentResetRequested extends VentEvent {}
