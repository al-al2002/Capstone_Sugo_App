import 'delivery_fee.dart';
import 'device_category.dart';
import 'issue_catalog.dart';
import 'job_enums.dart';

class LaborPrice {
  const LaborPrice(this.symptom, this.fee);

  final String symptom;
  final String fee;
}

class LaborPriceCatalog {
  const LaborPriceCatalog._();

  /// A home visit's travel fee: ONE trip of the rule in [DeliveryFee]. A shop
  /// repair's pickup and delivery is two trips - [DeliveryFee.total], since
  /// 2026-11-17 - and is not this.
  static int? travelFee(double? distanceKm) =>
      distanceKm == null ? null : DeliveryFee.calculate(distanceKm).oneWay;

  /// The urgent fee's share of the labor: 20% (2026-11-17, the user's rule -
  /// "symptom cost 600, plus 20% urgent fee, is 120").
  static const double urgentRate = 0.20;

  /// The labor fee as a number of pesos, or null when it is not one flat
  /// amount ("₱800/camera").
  static int? laborAmount(LaborPrice labor) {
    if (labor.fee.contains('/')) return null;
    return int.tryParse(labor.fee.replaceAll(RegExp(r'[^0-9]'), ''));
  }

  /// 20% of the labor, rounded to the peso, for an urgent job. Null when the
  /// labor is not one flat amount - the screen then says "+20% of labor".
  static int? urgentFee(LaborPrice labor) {
    final int? amount = laborAmount(labor);
    return amount == null ? null : (amount * urgentRate).round();
  }

  static String estimatedTotal({
    required LaborPrice labor,
    required int travelFee,
    int urgentFee = 0,
  }) {
    final int? amount = laborAmount(labor);
    if (amount == null) {
      return 'See labor fee + ₱${travelFee + urgentFee}';
    }
    return '₱${_grouped(amount + urgentFee + travelFee)}';
  }

  /// "1250" -> "1,250", so a total reads like the catalogue's own prices.
  static String _grouped(int pesos) => pesos.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (Match m) => '${m[1]},',
  );

  static LaborPrice? forJob({
    required DeviceType deviceType,
    required String symptomCode,
  }) {
    final DeviceCategory category = DeviceCategory.forJob(
      deviceType: deviceType,
      symptomCode: symptomCode,
    );
    final Map<String, String> fees = <String, String>{
      'laptop_slow_or_freezing': '₱500',
      'laptop_wont_power_on': '₱750',
      'laptop_blue_screen': '₱600',
      'laptop_screen_broken': '₱750',
      'laptop_battery_not_charging': '₱500',
      'laptop_overheating': '₱600',
      'laptop_input_dead': '₱600',
      'laptop_malware': '₱500',
      'laptop_no_os': '₱500',
      // ---- Maintenance and installation (2026-11-16), priced for Davao.
      //
      // Researched on 2026-11-16 for the user, Davao sources first. Where no
      // Davao rate is published, the Philippine figure is used and marked.
      // One figure each, not a range, because `estimatedTotal` adds the
      // travel fee to it. Sources and the reasoning per row are in
      // docs/maintenance-installation.md.
      //
      // Davao: one shop's minimum repair charge is ₱750; PH shops ask
      // ₱900-₱2,000 for a laptop clean; thermal paste is ₱150 in Davao.
      'laptop_cleaning_tune_up': '₱1,000',
      'phone_screen_cracked': '₱400',
      'phone_battery_drain': '₱350',
      'phone_wont_power_on': '₱600',
      'phone_charging_port': '₱450',
      'phone_camera_dead': '₱450',
      'phone_water_damage': '₱700',
      'phone_software_stuck': '₱300',
      'phone_audio_dead': '₱400',
      // PH: port clean-out ₱250-₱450; battery checks are often free.
      'phone_checkup': '₱300',
      'appliance_no_power': '₱500',
      'appliance_strange_noise': '₱500',
      'appliance_not_cooling': '₱700',
      'appliance_water_leak': '₱600',
      'appliance_electrical_fault': '₱700',
      'appliance_part_replacement': '₱500',
      // Davao (HandledPH 2026): window ₱500-₱800, split basic ₱800-₱1,200.
      'appliance_aircon_cleaning': '₱800',
      // PH home-service check-up fees: ₱450-₱600.
      'appliance_checkup': '₱500',
      // Davao installer: window ₱1,000-₱2,000.
      'appliance_aircon_install_window': '₱1,500',
      // Davao installer: 1.0-1.5 HP split ₱2,500-₱4,500, 3 m piping included.
      'appliance_aircon_install_split': '₱3,500',
      // ESTIMATE: no published PH rate found. Set beside the ₱750 Davao
      // minimum repair charge; confirm with a local technician.
      'appliance_tv_mounting': '₱800',
      // PH: ₱450 (Teko) to ₱500-₱700 for newer models.
      'appliance_washer_install': '₱500',
      'network_no_internet': '₱350',
      'network_weak_signal': '₱500',
      'network_router_dead': '₱500',
      'network_new_install': '₱800',
      // PH technician check-up fees: ₱500 (Globe), ₱300-₱500 (independents).
      'network_checkup': '₱500',
      'network_device_wont_connect': '₱300',
      'cctv_new_install': '₱800/camera',
      'cctv_no_video': '₱600',
      'cctv_offline': '₱400',
      'cctv_recorder_dead': '₱700',
      'cctv_night_vision': '₱500',
      'cctv_cable_damage': '₱600',
      'cctv_expand_system': '₱800/camera',
    };
    final String? fee = fees[symptomCode];
    if (fee == null) return null;
    return LaborPrice(
      IssueCatalog.byCode(symptomCode)?.label ?? category.label,
      fee,
    );
  }

  static const Map<DeviceCategory, List<LaborPrice>> byCategory =
      <DeviceCategory, List<LaborPrice>>{
        DeviceCategory.laptop: <LaborPrice>[
          LaborPrice('Laptop slow or freezing', '₱500'),
          LaborPrice("Laptop won't power on", '₱750'),
          LaborPrice('Blue screen error', '₱600'),
          LaborPrice('Broken screen replacement', '₱750'),
          LaborPrice('Battery not charging', '₱500'),
          LaborPrice('Overheating', '₱600'),
          LaborPrice('Keyboard or touchpad not working', '₱600'),
          LaborPrice('Virus or malware removal', '₱500'),
          LaborPrice('Operating system installation', '₱500'),
        ],
        DeviceCategory.phone: <LaborPrice>[
          LaborPrice('Cracked screen replacement', '₱400'),
          LaborPrice('Battery drains quickly', '₱350'),
          LaborPrice("Phone won't power on", '₱600'),
          LaborPrice('Charging port replacement', '₱450'),
          LaborPrice('Camera not working', '₱450'),
          LaborPrice('Water damage', '₱700'),
          LaborPrice('Software stuck / bootloop', '₱300'),
          LaborPrice('Speaker or microphone not working', '₱400'),
        ],
        DeviceCategory.appliance: <LaborPrice>[
          LaborPrice("Appliance won't turn on", '₱500'),
          LaborPrice('Strange noise', '₱500'),
          LaborPrice('Not cooling', '₱700'),
          LaborPrice('Water leaking', '₱600'),
          LaborPrice('Electrical problem', '₱700'),
          LaborPrice('Part replacement', '₱500'),
        ],
        DeviceCategory.network: <LaborPrice>[
          LaborPrice('No internet connection', '₱350'),
          LaborPrice('Weak Wi-Fi signal', '₱500'),
          LaborPrice('Router not working', '₱500'),
          LaborPrice('New network installation', '₱800'),
          LaborPrice('Device cannot connect to Wi-Fi', '₱300'),
        ],
        DeviceCategory.cctv: <LaborPrice>[
          LaborPrice('New CCTV installation', '₱800/camera'),
          LaborPrice('No video/display', '₱600'),
          LaborPrice('CCTV offline', '₱400'),
          LaborPrice('DVR/NVR recorder not working', '₱700'),
          LaborPrice('Night vision not working', '₱500'),
          LaborPrice('Damaged CCTV cable', '₱600'),
          LaborPrice('CCTV system expansion', '₱800/camera'),
        ],
      };
}
