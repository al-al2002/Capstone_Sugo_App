# Maintenance and installation in posting, with Davao prices

Added 2026-11-16 at the user's request. Before this, the home screen's
**Maintenance** and **Installation** tiles only picked a device. The client
then had to find a tune-up or an aircon install in a list of faults that did
not include either.

## What changed

| Where | Before | Now |
| --- | --- | --- |
| Issue catalogue | Faults only, plus three install rows | Each issue has a kind: `repair`, `maintenance` or `installation` (`IssueKind`). There are 9 new rows. |
| Home screen tiles | The answer picked a device | The answer picks the device and, where it names one, the exact problem (`ServiceOffers`) |
| Posting, step 1 | Device cards only | Device cards for a repair, plus Maintenance and Installation cards that open the same sheet as the home screen |
| Posting, step 3 | One flat dropdown | The dropdown is grouped under Repairs, Maintenance and Installation headings. The damage question is shown for repairs only, and maintenance or installation jobs show what is included. |

There is no schema or server change. `jobs.problem_symptom` stores the new
codes the same way it stores the old ones. RB-CARS matches on the device, so
a maintenance job reaches the same technicians as a repair on that device.
`skill_tags` scoring gives credit for related tags: `appliance_aircon_cleaning`
shares tokens with a tag such as `aircon_cleaning`. Nothing on the server
checks the codes against a list.

One guard was added: picking a maintenance or installation job clears any
"yes, it is damaged" answer left over from a repair picked earlier. Damage is
an input to the rules, so a leftover answer would send an aircon cleaning to
the shop.

## The new services

| Code | Label | Device card | Route | Kind |
| --- | --- | --- | --- | --- |
| `laptop_cleaning_tune_up` | Tune-up and cleaning | Laptop / PC | Home service | Maintenance |
| `phone_checkup` | Battery and charging-port check-up | Phone / Tablet | Shop | Maintenance |
| `appliance_aircon_cleaning` | Aircon cleaning | Appliance | Home service | Maintenance |
| `appliance_checkup` | Appliance check-up | Appliance | Home service | Maintenance |
| `network_checkup` | Wi-Fi check-up | Network / Wi-Fi | Home service | Maintenance |
| `appliance_aircon_install_window` | Aircon installation: window type | Appliance | Home service | Installation |
| `appliance_aircon_install_split` | Aircon installation: split type | Appliance | Home service | Installation |
| `appliance_tv_mounting` | TV wall mounting | Appliance | Home service | Installation |
| `appliance_washer_install` | Washing machine installation | Appliance | Home service | Installation |

Three existing rows are now marked as installation: `network_new_install`,
`cctv_new_install` and `cctv_expand_system`.

## Prices (researched 2026-11-16)

These are labor only. The travel or delivery fee is added on top by the
existing rule (₱50 up to 3 km, then ₱15 for each km after that). Each price is
a single figure, not a range, because `LaborPriceCatalog.estimatedTotal` adds
the travel fee to it.

Davao sources were used first. Where no Davao rate is published, the
Philippine-wide figure is used and marked as such. Most published prices come
from the businesses that sell the service, so they are reference points, not a
market survey.

| Service | SUGO price | Evidence | Reasoning |
| --- | --- | --- | --- |
| Aircon cleaning | **₱800** | Davao 2026: window ₱500–₱800, basic split ₱800–₱1,200 ([HandledPH](https://handledph.com/aircon-cooling/aircon-cleaning-davao/)). One Davao listing shows ₱450 ([filipinopo](https://www.filipinopo.com/aircon-repair-installation-cleaning-davao-city-949783)). | ₱800 is where the two types meet: the top of window, the bottom of split. The hint says window costs less. |
| Aircon install, window | **₱1,500** | Davao installer: ₱1,000–₱2,000 ([HandledPH](https://handledph.com/aircon-cooling/aircon-installation-davao/)) | Middle of the Davao range. |
| Aircon install, split | **₱3,500** | Davao installer: ₱2,500–₱4,500 for 1.0–1.5 HP, about 3 m of piping included ([HandledPH](https://handledph.com/aircon-cooling/aircon-installation-davao/)). PH-wide: ₱3,000–₱6,000 ([aircon.ph](https://aircon.ph/price-guides/aircon-installation-price-guide/)). | Middle of the Davao range. The hint says longer piping costs extra. |
| Washing machine install | **₱500** | PH: ₱450 check-up/installation fee ([Teko](https://teko.ph/washing-machine-service)); ₱500–₱700 for newer models ([Riantalks](https://riantalks.com/washing-machine-repair-price-rates-philippines/)) | Low end, matching the simplest installs. |
| TV wall mounting | **₱800** | **No published Philippine rate found.** Only US prices were available. | **Estimate.** It is set beside a Davao shop's ₱750 minimum repair charge ([STSPhil](https://stsphiltech.vercel.app/)) and should be confirmed with a local technician before the defence. |
| Laptop tune-up and cleaning | **₱1,000** | Davao: ₱750 minimum repair charge ([STSPhil](https://stsphiltech.vercel.app/)); thermal paste from ₱150 ([DFE Davao](https://dfestore.com/product-category/00055/)). PH shops: ₱900–₱2,000 ([PCForge](https://pcforgeph.com/product/laptop-deep-cleaning/), [vBuilt](https://vbuiltpc.setmore.com/), [ElitePC](https://elitepcph.com/packages)) | Above the Davao minimum and at the low end of the PH range, since Davao rates run below Metro Manila. |
| Phone check-up | **₱300** | PH: port clean-out ₱250–₱450 ([ACJ Electronics](https://acjelectronics.com/blog/charging-port-repair/)). Battery checks are often free. | Low end of the port clean-out range. |
| Appliance check-up | **₱500** | PH home-service check-up fees: ₱450 ([Teko](https://teko.ph/washing-machine-service)), ₱600 ([HeyGoldie](https://book.heygoldie.com/ayusin-net)) | Between the two. |
| Wi-Fi check-up | **₱500** | PH: technician check-up ₱500 ([Globe](https://gfiberprepaid.globe.com.ph/serviceability/terms&conditions)); independent technicians charge ₱300–₱500 extra for network work ([TipidPC](https://tipidpc.com/viewtopic.php?tid=176090)) | Matches the Globe fee. |
| Router or Wi-Fi install (existing) | ₱800 (unchanged) | PH ISP installations, which include the line: ₱699–₱2,500 ([grit.ph](https://grit.ph/internet-plans/)) | A technician setup without a new line sits below ISP fees. Kept. |
| CCTV install (existing) | ₱800/camera (unchanged) | PH: ₱800–₱2,000 labor per camera ([GoodHand](https://shop.goodhand88.com/blog/cctv-installation-cost-philippines.html)). Davao packages include installation ([Davao CCTV](https://www.davaocctv.com/)). | Low end of the PH range, which fits Davao. Kept. |

Step 1 shows a starting price on each card ("From ₱300" for Maintenance,
"From ₱500" for Installation). Each row in the sheet shows its own price, or
"From …" when the row covers several jobs.

## The redesigned flow

The same frame (`PostingScaffold`) wraps all six steps, so the redesign applies
to every step:

- **A navy header** with the same navy-to-blue gradient as the home screen's
  hero. It holds the step question, a faint icon for the step, and a
  "Step 3 of 6 · Problem" pill.
- **Progress that moves.** The current step's segment fills as the screen
  arrives.
- **Staggered content.** Sections rise into place a few frames apart, top
  first (`AppMotion.staggerStep`).
- **Slide between steps.** `PostingRoute` moves forward to the left and back
  to the right, the same direction the rail fills.
- **Press feedback.** Cards shrink slightly under the finger (`PressScale`).
- The service sheet rows animate in the same staggered way.

All motion turns into an instant change when the phone's reduce-motion setting
is on (`AppMotion.reduced`).

Step 1 also got a bug fix. The device cards' `Stack` defaulted to top-left
alignment, so each card's icon and label sat against the left edge instead of
in the centre. The grid is now 3 columns (2 below 330dp), so the new
Maintenance and Installation cards fit above the Continue bar on a normal
phone.

## Tests

`test/features/rb_cars/maintenance_installation_test.dart` checks:

- every issue has a price and a unique code, and the researched prices are
  the ones in the table above;
- every offer lands on real issues of its own kind and device;
- price labels: a single price, a shared per-camera price, and "From";
- a leftover damage answer is cleared when a maintenance job is picked;
- step 1, Maintenance, then a service, goes straight to step 2 with the
  device and the problem chosen;
- step 3 has no damage question for maintenance, and its list is grouped;
- the home screen sheet hands back the exact problem.

The goldens `device_type_grid.png` and `posting_flow.png` were regenerated
after review.
