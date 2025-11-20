import 'package:audioplayers/audioplayers.dart';

class AlarmAudioPlayer {
  static final AudioPlayer _player = AudioPlayer();
  static AudioPlayer get instance => _player;
} 