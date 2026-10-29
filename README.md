# Nông Trại Của Em Gái

Bộ source sạch tương ứng với bản thử nghiệm ngày 12/10/2026 (`0.1.7-test-20261012`, fix8).

## Mở và chạy project

1. Cài Godot Engine 4.6 hoặc 4.6.1.
2. Trong Godot Project Manager, chọn **Import** và trỏ tới `project.godot`.
3. Chờ Godot import lại asset lần đầu.
4. Nhấn **F5** để chạy `scenes/main.tscn`.

## Xuất bản Android

1. Cấu hình Android SDK/JDK trong Godot Editor Settings.
2. Kiểm tra `export_presets.cfg`.
3. Chọn **Project > Export > Android** để tạo APK/AAB mới.
4. Không commit keystore, mật khẩu ký ứng dụng hoặc file APK vào source.

Cache Godot, backup lịch sử, báo cáo QA, build Android và artifact xuất game đã được loại khỏi repository. Godot sẽ tự tạo lại cache cần thiết.

## Trạng thái gameplay

Updated 2026-10-03. The current boot is `project.godot` -> `scenes/main.tscn` -> `scripts/main_v3.gd`, with `GameState` and `ScreenRouter` autoloads. **Do not use the legacy renderer `scripts/main.gd` as runtime authority.**

Open `project.godot` in Godot 4.6.1 and press F5. Start at Title, select a save slot, then Home. Field opens through Field Select; the canonical farm is `scenes/screens/05_field_gameplay.tscn`.

The approved 12 plots, current plot geometry, 400 starting coins, 100 daily energy and Carrot -> Tomato -> Pumpkin order chain remain authoritative over conflicting older GDD numbers.

Home now exposes Map, Workshop, Companions and Calendar. These use one shared journal scene backed by nine JSON tables in `data/full_game/`. Seven island unlocks, buildings, medicinal gardens, species food/cures, care/utility, crafting, dragon eggs, seasonal fairs and rare-fruit pity persist through the existing save service. The journal is a functional data-driven page, not a claim of completed species/island production art.

Current saves: three `user://my_sisters_farm_slot_N.save` files using the existing MSF3 format, with additive state version 4. Existing items and valid plot state are preserved on load. QA runs must set `MSF_TEST_SAVE_DIR` to an isolated directory; never run fresh-save tests on a player's slots.

## Historical V2 notes (superseded; retained for provenance)

Project Godot 4 nay dung duy nhat `MY_SISTERS_FARM_CANONICAL_V2` lam visual/runtime source of truth.

## Da co gi

- Title -> save slot -> Home Hub flow.
- Field 12 plot doc lap dung toa do V2 va 5 layer rieng: `BaseSoil`, `StateOverlay`, `CropSprite`, `ReadyOverlay`, `SelectionOverlay`.
- Carrot/Tomato/Pumpkin world sprites; khong dung inventory icon tren ruong.
- Farmer canonical green dress + cream apron + red ribbon + straw hat, 10 frame/action.
- Shop, Storage, Settings, Animal va Dragon Island dung V2 runtime art.
- Save V2 duoc luu tai `user://my_sisters_farm_v2.save`.

## Flow chinh

1. `Home Hub`
2. Click `Ruong` -> `Field Interaction`
3. Click `Chuong` -> `Animal Entry` -> `Animal Inside`
4. `Kho / Shop / Pet / Ban do / Event / Reward / House / Craft` mo bang overlay rieng

## Choi thu nhanh

1. Mo Godot 4.6.1 hoac moi hon.
2. Import file `project.godot`.
3. Nhan `F5`.
4. Vao thang `Home Hub`.
5. Click `Ruong` de vao man ruong:
   - Chon 1 o dat.
   - Bam `Cay`, `Hat`, `Gieo`, `Tuoi`.
   - Bam `Ngay moi` de cay lon.
   - Bam `Thu` khi cay da chin.
6. Click `Chuong` de vao man chuong:
   - Bam `Cho an`, `Don dep`, `Vuot ve`, `Thu trung`.

## File quan trong

- `project.godot`
- `scenes/main.tscn`
- `scripts/main.gd`
- `scripts/farm_data.gd`
- `assets/canonical_v2/03_ART_RUNTIME_READY/`
- `docs/canonical_v2/`
- `data/asset_mapping.json`
- `docs/source_curation.md`

## Ghi chu cleanup

- Project combat cu da duoc dua ra khoi root project va chuyen den:
  `C:\Users\HanTin\Documents\archive_old_project_20260424_jxnhalam_games`
- Thu muc project hien tai chi giu phan can cho Nong Trai Vui Ve.
