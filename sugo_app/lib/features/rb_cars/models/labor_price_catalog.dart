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

  static int? travelFee(double? distanceKm) {
    if (distanceKm == null) return null;
    if (distanceKm <= 3) return 50;
    return 50 + ((distanceKm - 3).ceil() * 15);
  }

  static String estimatedTotal({
    required LaborPrice labor,
    required int travelFee,
  }) {
    final String digits = labor.fee.replaceAll(RegExp(r'[^0-9]'), '');
    final int? amount = int.tryParse(digits);
    if (amount == null || labor.fee.contains('/')) {
      return 'See labor fee + ₱$travelFee';
    }
    return '₱${amount + travelFee}';
  }

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
      'phone_screen_cracked': '₱400',
      'phone_battery_drain': '₱350',
      'phone_wont_power_on': '₱600',
      'phone_charging_port': '₱450',
      'phone_camera_dead': '₱450',
      'phone_water_damage': '₱700',
      'phone_software_stuck': '₱300',
      'phone_audio_dead': '₱400',
      'appliance_no_power': '₱500',
      'appliance_strange_noise': '₱500',
      'appliance_not_cooling': '₱700',
      'appliance_water_leak': '₱600',
      'appliance_electrical_fault': '₱700',
      'appliance_part_replacement': '₱500',
      'network_no_internet': '₱350',
      'network_weak_signal': '₱500',
      'network_router_dead': '₱500',
      'network_new_install': '₱800',
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
