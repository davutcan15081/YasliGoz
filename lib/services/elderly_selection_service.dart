import 'package:flutter/foundation.dart';
import '../models/elderly_person.dart';

class ElderlySelectionService extends ChangeNotifier {
  ElderlyPerson? _selectedElderly;
  
  ElderlyPerson? get selectedElderly => _selectedElderly;
  
  bool get hasSelectedElderly => _selectedElderly != null;
  
  void selectElderly(ElderlyPerson elderly) {
    _selectedElderly = elderly;
    notifyListeners();
  }
  
  void clearSelection() {
    _selectedElderly = null;
    notifyListeners();
  }
  
  String get selectedElderlyId => _selectedElderly?.id ?? '';
  String get selectedElderlyName => _selectedElderly?.name ?? 'Seçili Kişi Yok';
} 