#!/usr/bin/env python3
import argparse
import plistlib
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("plist")
    parser.add_argument("--flavor", choices=["cn", "intl"], required=True)
    args = parser.parse_args()

    plist_path = Path(args.plist)
    if not plist_path.exists():
        raise SystemExit(f"plist not found: {plist_path}")

    with plist_path.open("rb") as f:
        data = plistlib.load(f)

    flavor = args.flavor
    data["flutter.has_logged_in"] = True
    data["flutter.logged_in_phone"] = "DemoAccount"
    data["flutter.logged_in_auth_provider"] = "demo"
    data["flutter.app_mode"] = flavor
    data["flutter.app_mode_locked"] = True
    data["flutter.demo_data_seeded"] = False

    if flavor == "intl":
        data["flutter.logged_in_display_name"] = "AI Money Demo"
        data["flutter.logged_in_email"] = "demo@aimoneyledger.app"
        data["flutter.app_locale"] = "en_US"
        data["flutter.app_country_code"] = "US"
        data["flutter.app_base_currency"] = "USD"
    else:
        data["flutter.logged_in_display_name"] = "DemoAccount"
        data.pop("flutter.logged_in_email", None)
        data["flutter.app_locale"] = "zh_CN"
        data["flutter.app_country_code"] = "CN"
        data["flutter.app_base_currency"] = "CNY"

    stale_prefixes = (
        "flutter.account_entries",
        "flutter.cloud_assets_v2_",
        "flutter.stock_positions_v2_",
        "flutter.vip_expire_ms_",
        "flutter.vip_type_",
    )
    for key in list(data.keys()):
        if key.startswith(stale_prefixes):
            data.pop(key, None)

    with plist_path.open("wb") as f:
        plistlib.dump(data, f)

    print(f"configured {plist_path} for {flavor} demo mode")


if __name__ == "__main__":
    main()
