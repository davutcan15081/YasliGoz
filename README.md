# YaşlıGöz - GPS Tabanlı Yaşlı Takip Uygulaması

<div align="center">
  <img src="screenshots/slogan.png" alt="YaşlıGöz Logo" width="400"/>

  <p><strong>Sevdiklerinizin güvenliği için akıllı takip çözümü</strong></p>

  [![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
  [![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com)
  [![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
</div>

## 📱 Uygulama Önizlemesi

<div align="center">
  <table>
    <tr>
      <td align="center">
        <img src="screenshots/anaekran.png" alt="Ana Ekran" width="250"/>
        <br />
        <sub><b>Ana Ekran</b></sub>
      </td>
      <td align="center">
        <img src="screenshots/takiplistesi.png" alt="Takip Listesi" width="250"/>
        <br />
        <sub><b>Takip Listesi</b></sub>
      </td>
      <td align="center">
        <img src="screenshots/ailepaneli.png" alt="Aile Paneli" width="250"/>
        <br />
        <sub><b>Aile Paneli</b></sub>
      </td>
    </tr>
    <tr>
      <td align="center">
        <img src="screenshots/guvenlialan.png" alt="Güvenli Alan" width="250"/>
        <br />
        <sub><b>Güvenli Alan Tanımlama</b></sub>
      </td>
      <td align="center">
        <img src="screenshots/yasliekran-1.png" alt="Yaşlı Ekranı" width="250"/>
        <br />
        <sub><b>Yaşlı Kullanıcı Arayüzü</b></sub>
      </td>
      <td align="center">
        <img src="screenshots/yasliekran-2.png" alt="Yaşlı Ekranı 2" width="250"/>
        <br />
        <sub><b>Kolay Kullanım Paneli</b></sub>
      </td>
    </tr>
  </table>
</div>

## 🎯 Proje Hakkında

YaşlıGöz, yaşlı bireylerin güvenliğini sağlamak ve ailelerinin onları kolayca takip edebilmesini sağlamak için geliştirilmiş kapsamlı bir mobil uygulamadır. GPS teknolojisi, Firebase altyapısı ve kullanıcı dostu arayüzü ile sevdiklerinizin her zaman güvende olmasını sağlar.

## ✨ Özellikler

### 🔍 Gerçek Zamanlı Takip
- GPS tabanlı anlık konum izleme
- Harita üzerinde gerçek zamanlı konum gösterimi
- Geçmiş konum verileri ve rota izleme
- Arka planda sürekli konum güncelleme

### 🛡️ Güvenlik Özellikleri
- Güvenli alan (Geofencing) tanımlama
- Güvenli alandan çıkış bildirimleri
- Acil durum bildirimleri
- Şifreli veri iletişimi

### 👨‍👩‍👧‍👦 Aile Yönetimi
- Çoklu kullanıcı takibi
- Aile üyeleri paneli
- Kolay kullanıcı ekleme/çıkarma
- Rol bazlı erişim yönetimi

### 🎤 İletişim
- Sesli mesaj gönderme/alma
- Anlık bildirimler
- Firebase Cloud Messaging entegrasyonu

### 🔋 Akıllı Özellikler
- Batarya durumu izleme
- Düşük batarya uyarıları
- Ağ bağlantı durumu kontrolü
- Otomatik senkronizasyon

### 👴 Yaşlı Dostu Arayüz
- Büyük ve okunaklı butonlar
- Basit ve anlaşılır menüler
- Kolay navigasyon
- Sesli yönlendirmeler

## 🛠️ Kullanılan Teknolojiler

### Framework & Dil
- **Flutter** (SDK ^3.8.1) - Cross-platform mobil uygulama geliştirme
- **Dart** - Programlama dili

### Backend & Veritabase
- **Firebase Core** (^3.15.0) - Firebase temel altyapısı
- **Firebase Authentication** (^5.6.1) - Kullanıcı kimlik doğrulama
- **Firebase Realtime Database** (^11.3.8) - Gerçek zamanlı veritabanı
- **Firebase Storage** (^12.4.8) - Dosya depolama
- **Firebase Messaging** (^15.2.8) - Push bildirimleri

### Konum & Harita
- **Geolocator** (^12.0.0) - GPS konum servisleri
- **Flutter Map** (^6.1.0) - Harita gösterimi
- **LatLong2** (^0.9.1) - Koordinat hesaplamaları

### Servisler & Özellikler
- **Flutter Background Service** (^5.1.0) - Arka plan işlemleri
- **Flutter Local Notifications** (^17.2.4) - Yerel bildirimler
- **Audio Players** (^6.5.0) - Ses çalma
- **Record** (^6.0.0) - Ses kaydetme
- **Battery Plus** (^6.0.2) - Batarya durumu
- **Device Info Plus** (^9.1.2) - Cihaz bilgileri
- **Connectivity Plus** (^6.0.3) - Ağ bağlantısı kontrolü

### Güvenlik
- **Encrypt** (^5.0.1) - Şifreleme
- **Flutter Secure Storage** (^9.0.0) - Güvenli veri depolama
- **Crypto** (^3.0.3) - Kriptografi

### Diğer
- **Provider** (^6.1.2) - State management
- **Shared Preferences** (^2.2.2) - Yerel veri saklama
- **URL Launcher** (^6.3.0) - URL açma
- **HTTP** (^1.2.1) - HTTP istekleri
- **Purchases Flutter** (^8.10.4) - Premium abonelik yönetimi

## 📦 Kurulum

### Gereksinimler
- Flutter SDK (^3.8.1)
- Dart SDK
- Android Studio / VS Code
- Firebase hesabı

### Adımlar

1. **Projeyi Klonlayın**
```bash
git clone https://github.com/davutcan15081/YasliGoz.git
cd YasliGoz
```

2. **Bağımlılıkları Yükleyin**
```bash
flutter pub get
```

3. **Firebase Yapılandırması**
   - Firebase Console'da yeni bir proje oluşturun
   - Android ve iOS uygulamalarınızı ekleyin
   - `google-services.json` (Android) ve `GoogleService-Info.plist` (iOS) dosyalarını indirip ilgili klasörlere ekleyin

4. **Uygulamayı Çalıştırın**
```bash
flutter run
```

## 🏗️ Proje Yapısı

```
lib/
├── main.dart           # Uygulama giriş noktası
├── models/            # Veri modelleri
├── screens/           # Ekran widget'ları
└── services/          # Servis katmanı (Firebase, GPS, vb.)
```

## 🚀 Kullanım

1. **Kayıt Olma**: Uygulamayı ilk açtığınızda hesap oluşturun
2. **Aile Üyesi Ekleme**: Ana ekrandan takip edilecek kişileri ekleyin
3. **Güvenli Alan Tanımlama**: Harita üzerinde güvenli bölgeler belirleyin
4. **Bildirimleri Aktif Etme**: Anlık uyarılar için bildirimlere izin verin
5. **Takip Başlatma**: Gerçek zamanlı konum takibini başlatın

## 📸 Ekran Görüntüleri Hakkında

Uygulama aşağıdaki temel ekranları içerir:
- **Ana Ekran**: Genel kontrol paneli ve hızlı erişim
- **Takip Listesi**: Aktif takip edilen kullanıcılar
- **Aile Paneli**: Aile üyelerinin yönetimi
- **Güvenli Alan**: Coğrafi sınırların belirlenmesi
- **Yaşlı Arayüzü**: Basitleştirilmiş kullanıcı deneyimi

## 🔐 Güvenlik

- Tüm kullanıcı verileri Firebase Authentication ile korunur
- Konum verileri şifrelenmiş olarak saklanır
- Secure Storage kullanılarak hassas bilgiler cihazda güvenle tutulur
- HTTPS protokolü ile güvenli veri iletimi

## 📝 Lisans

Bu proje portföy projesi olarak geliştirilmiştir.

## 👨‍💻 Geliştirici

**Davut Can**
- GitHub: [@davutcan15081](https://github.com/davutcan15081)

## 🤝 Katkıda Bulunma

Bu proje bir portföy projesidir, ancak önerileriniz için issue açabilirsiniz.

## 📧 İletişim

Proje hakkında sorularınız için GitHub üzerinden iletişime geçebilirsiniz.

---

<div align="center">
  <p>❤️ Flutter ile geliştirildi</p>
  <p>Made with ❤️ using Flutter</p>
</div>
