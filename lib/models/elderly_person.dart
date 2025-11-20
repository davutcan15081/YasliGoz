class ElderlyPerson {
  final String id;
  final String name;
  final String phoneNumber;
  final String address;
  final List<EmergencyContact> emergencyContacts;
  final List<String> allergies;
  final List<String> medications;
  final List<String> chronicDiseases;
  final String notes;
  final DateTime createdAt;
  // Cihaz bilgileri
  final String? deviceId; // Cihazın benzersiz ID'si
  final String? deviceName; // Cihaz adı (örn: "Dede'nin Telefonu")
  final String? fcmToken; // FCM token'ı
  final bool isDeviceActive; // Cihaz aktif mi?

  ElderlyPerson({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.address,
    this.emergencyContacts = const [],
    this.allergies = const [],
    this.medications = const [],
    this.chronicDiseases = const [],
    this.notes = '',
    required this.createdAt,
    this.deviceId,
    this.deviceName,
    this.fcmToken,
    this.isDeviceActive = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phoneNumber': phoneNumber,
      'address': address,
      'emergencyContacts': emergencyContacts.map((e) => e.toMap()).toList(),
      'allergies': allergies,
      'medications': medications,
      'chronicDiseases': chronicDiseases,
      'notes': notes,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'fcmToken': fcmToken,
      'isDeviceActive': isDeviceActive,
    };
  }

  factory ElderlyPerson.fromMap(Map<String, dynamic> map) {
    try {
      return ElderlyPerson(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? '',
        phoneNumber: map['phoneNumber']?.toString() ?? '',
        address: map['address']?.toString() ?? '',
        emergencyContacts: _parseEmergencyContacts(map['emergencyContacts']),
        allergies: _parseStringList(map['allergies']),
        medications: _parseStringList(map['medications']),
        chronicDiseases: _parseStringList(map['chronicDiseases']),
        notes: map['notes']?.toString() ?? '',
        createdAt: _parseDateTime(map['createdAt']),
        deviceId: map['deviceId']?.toString(),
        deviceName: map['deviceName']?.toString(),
        fcmToken: map['fcmToken']?.toString(),
        isDeviceActive: map['isDeviceActive'] == true,
      );
    } catch (e) {
      print('ElderlyPerson fromMap hatası: $e');
      // Varsayılan değerlerle döndür
      return ElderlyPerson(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Bilinmeyen',
        phoneNumber: map['phoneNumber']?.toString() ?? '',
        address: map['address']?.toString() ?? '',
        emergencyContacts: [],
        allergies: [],
        medications: [],
        chronicDiseases: [],
        notes: '',
        createdAt: DateTime.now(),
        deviceId: map['deviceId']?.toString(),
        deviceName: map['deviceName']?.toString(),
        fcmToken: map['fcmToken']?.toString(),
        isDeviceActive: false,
      );
    }
  }

  static List<EmergencyContact> _parseEmergencyContacts(dynamic data) {
    try {
      if (data is List) {
        return data.map((item) {
          if (item is Map) {
            final Map<String, dynamic> contactMap = {};
            item.forEach((key, value) {
              if (key != null) {
                contactMap[key.toString()] = value;
              }
            });
            return EmergencyContact.fromMap(contactMap);
          }
          return EmergencyContact(name: '', phoneNumber: '', relationship: '');
        }).toList();
      }
      return [];
    } catch (e) {
      print('EmergencyContacts parse hatası: $e');
      return [];
    }
  }

  static List<String> _parseStringList(dynamic data) {
    try {
      if (data is List) {
        return data.map((item) => item?.toString() ?? '').where((item) => item.isNotEmpty).toList();
      }
      return [];
    } catch (e) {
      print('StringList parse hatası: $e');
      return [];
    }
  }

  static DateTime _parseDateTime(dynamic data) {
    try {
      if (data is int) {
        return DateTime.fromMillisecondsSinceEpoch(data);
      } else if (data is String) {
        final timestamp = int.tryParse(data);
        if (timestamp != null) {
          return DateTime.fromMillisecondsSinceEpoch(timestamp);
        }
      }
      return DateTime.now();
    } catch (e) {
      print('DateTime parse hatası: $e');
      return DateTime.now();
    }
  }
}

class EmergencyContact {
  final String name;
  final String phoneNumber;
  final String relationship;

  EmergencyContact({
    required this.name,
    required this.phoneNumber,
    required this.relationship,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phoneNumber': phoneNumber,
      'relationship': relationship,
    };
  }

  factory EmergencyContact.fromMap(Map<String, dynamic> map) {
    try {
      return EmergencyContact(
        name: map['name']?.toString() ?? '',
        phoneNumber: map['phoneNumber']?.toString() ?? '',
        relationship: map['relationship']?.toString() ?? '',
      );
    } catch (e) {
      print('EmergencyContact fromMap hatası: $e');
      return EmergencyContact(name: '', phoneNumber: '', relationship: '');
    }
  }
} 