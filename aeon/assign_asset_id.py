# assign_asset_id.py — dijalankan lewat:  manage.py shell -c "exec(open(PATH).read())"
# (repo itcnelita/ocsaeon, task 0036). Aman dijalankan berulang (idempotent).
#
# 1) Pastikan custom field (accountinfo, target ASSET) AEON ada beserta pilihan dropdown-nya.
#    Field/pilihan yang sudah ada TIDAK dihapus atau diubah (bisa ditambah dari console).
# 2) Pastikan setiap aset punya baris accountinfo berisi semua field.
# 3) Beri Asset ID berurutan (AEON-IT-000001, ...) untuk aset yang belum punya.
#    ID yang sudah ada tidak pernah diubah. Status aset default "Aktif".
#
# Format nilai mengikuti frontend OCS 3:
#   TEXT/TEXTAREA -> "string",  SELECT -> {"value": <id pilihan>, "text": "<teks>"},  CHECKBOX -> [id, ...]
import os
import re

from accountinfo.models import AccountinfoConfig, AccountinfoData, AccountinfoValue
from asset.inventory_base.models import InventoryBase
from django.contrib.contenttypes.models import ContentType
from django.db import transaction

PREFIX = os.environ.get("AEON_ASSET_PREFIX", "AEON-IT-")
DIGITS = 6
DRY_RUN = os.environ.get("AEON_DRY_RUN") == "1"

FIELDS = [
    # (nama, deskripsi, tipe, pilihan awal)
    ("Asset ID", "Nomor aset IT AEON (tertera di label barcode)", "TEXT", []),
    ("Lokasi", "Store atau kantor tempat aset berada", "SELECT", ["HQ", "GMS", "SSM"]),
    ("Area", "Area di dalam lokasi", "SELECT",
     ["Kasir", "Backroom", "Area penjualan", "Admin/Office", "Ruang server", "Gudang"]),
    ("PIC", "Penanggung jawab / pengguna aset", "TEXT", []),
    ("Status aset", "Kondisi administrasi aset", "SELECT", ["Aktif", "Rusak", "Gudang", "Disposal"]),
    ("Stocktake terakhir", "Waktu stocktake terakhir (YYYY-MM-DD HH:MM)", "TEXT", []),
    ("Hasil stocktake", "Hasil stocktake terakhir", "SELECT", ["Sesuai", "Pindah lokasi", "Tidak ditemukan"]),
    ("Stocktake oleh", "Petugas stocktake terakhir", "TEXT", []),
]
DEFAULT_SELECT = {"Status aset": "Aktif"}


def log(*a):
    print(("[DRY] " if DRY_RUN else "") + " ".join(str(x) for x in a))


def ensure_fields():
    configs = {}
    for name, desc, dtype, options in FIELDS:
        cfg = AccountinfoConfig.objects.filter(name=name, datatarget="ASSET").first()
        if cfg is None:
            log("buat field:", name, f"({dtype})")
            if not DRY_RUN:
                cfg = AccountinfoConfig.objects.create(
                    name=name, description=desc, datatype=dtype, datatarget="ASSET")
        elif cfg.datatype != dtype:
            log(f"!! field '{name}' sudah ada dengan tipe {cfg.datatype} (bukan {dtype}); dibiarkan")
        if cfg is not None:
            existing = set(cfg.accountinfo_values.values_list("value", flat=True))
            for opt in options:
                if opt not in existing:
                    log("  tambah pilihan:", name, "->", opt)
                    if not DRY_RUN:
                        AccountinfoValue.objects.create(accountinfo_config=cfg, value=opt)
        configs[name] = cfg
    return configs


def empty_value(cfg):
    if cfg.datatype == "CHECKBOX":
        return []
    if cfg.datatype == "SELECT":
        return None
    return ""


def select_value(cfg, text):
    v = cfg.accountinfo_values.filter(value=text).first()
    return {"value": v.id, "text": v.value} if v else None


def next_number():
    pat = re.compile(r"^" + re.escape(PREFIX) + r"(\d+)$")
    asset_cfg = AccountinfoConfig.objects.filter(name="Asset ID", datatarget="ASSET").first()
    highest = 0
    if asset_cfg:
        key = str(asset_cfg.id)
        for data in AccountinfoData.objects.filter(object_slug="inventory_base.inventorybase"):
            val = (data.accountdata or {}).get(key) or ""
            m = pat.match(str(val).strip())
            if m:
                highest = max(highest, int(m.group(1)))
    return highest + 1


def run():
    configs = ensure_fields()
    if DRY_RUN and any(c is None for c in configs.values()):
        log("field belum ada; langkah aset dilewati pada dry-run")
        return
    ct = ContentType.objects.get_by_natural_key(app_label="inventory_base", model="inventorybase")
    asset_key = str(configs["Asset ID"].id)
    seq = next_number()
    created = assigned = 0
    with transaction.atomic():
        for asset in InventoryBase.objects.order_by("id"):
            data = AccountinfoData.objects.filter(
                object_slug="inventory_base.inventorybase", object_id=asset.id).first()
            if data is None:
                data = AccountinfoData(content_type=ct, object_id=asset.id,
                                       object_slug="inventory_base.inventorybase", accountdata={})
                created += 1
            accountdata = dict(data.accountdata or {})
            changed = data.pk is None
            for name, cfg in configs.items():
                key = str(cfg.id)
                if key not in accountdata:
                    accountdata[key] = empty_value(cfg)
                    changed = True
                if name in DEFAULT_SELECT and not accountdata.get(key):
                    val = select_value(cfg, DEFAULT_SELECT[name])
                    if val:
                        accountdata[key] = val
                        changed = True
            if not str(accountdata.get(asset_key) or "").strip():
                new_id = f"{PREFIX}{seq:0{DIGITS}d}"
                seq += 1
                accountdata[asset_key] = new_id
                assigned += 1
                changed = True
                log(f"Asset ID {new_id} -> aset #{asset.id} {asset.name} (serial {asset.serial})")
            if changed and not DRY_RUN:
                data.accountdata = accountdata
                data.save()
    log(f"selesai: aset={InventoryBase.objects.count()} baris accountinfo baru={created} Asset ID baru={assigned}")


run()
