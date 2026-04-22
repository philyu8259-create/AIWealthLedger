# -*- coding: utf-8 -*-
import json
import uuid
import os
import random
import string
import time
import hmac
import hashlib
import base64
import urllib.parse
import traceback
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
import ssl

DB_FILE = '/tmp/entries.json'
SMS_CODES_FILE = '/tmp/sms_codes.json'

# ─── 短信配置（从环境变量读取）──────────────────────────
ALIYUN_ACCESS_KEY_ID     = os.environ.get('ALIYUN_ACCESS_KEY_ID', '')
ALIYUN_ACCESS_KEY_SECRET  = os.environ.get('ALIYUN_ACCESS_KEY_SECRET', '')
ALIYUN_SMS_SIGN_NAME     = os.environ.get('ALIYUN_SMS_SIGN_NAME', 'AI财富账本')
ALIYUN_SMS_TEMPLATE_CODE = os.environ.get('ALIYUN_SMS_TEMPLATE_CODE', '')
SMS_REGION               = 'cn-hangzhou'

# ─── Apple 订阅校验配置 ─────────────────────────────
APP_STORE_SHARED_SECRET = os.environ.get('APP_STORE_SHARED_SECRET', '')
APPLE_VERIFY_URL = 'https://buy.itunes.apple.com/verifyReceipt'
SANDBOX_VERIFY_URL = 'https://sandbox.itunes.apple.com/verifyReceipt'

# ─── OTS 配置（SDK v5.4.1）──────────────
OTS_INSTANCE_NAME = os.environ.get('OTS_INSTANCE_NAME', 'ai-accountant-cu')
OTS_REGION = os.environ.get('OTS_REGION', 'cn-hangzhou')
OTS_ENDPOINT = f"https://{OTS_INSTANCE_NAME}.{OTS_REGION}.ots.aliyuncs.com"
OTS_ACCESS_KEY_ID = os.environ.get('OTS_ACCESS_KEY_ID', ALIYUN_ACCESS_KEY_ID)
OTS_ACCESS_KEY_SECRET = os.environ.get('OTS_ACCESS_KEY_SECRET', ALIYUN_ACCESS_KEY_SECRET)
OTS_TABLE = os.environ.get('OTS_TABLE', 'accounting_entries')
ASSET_TABLE = os.environ.get('ASSET_TABLE', 'asset_items')
STOCK_POSITIONS_TABLE = os.environ.get('STOCK_POSITIONS_TABLE', 'stock_positions')
VIP_TABLE = os.environ.get('VIP_TABLE', 'vip_profiles')

# OTS 客户端（延迟初始化）
_ots_client = None

def _get_ots_client():
    global _ots_client
    if _ots_client is None:
        import tablestore
        _ots_client = tablestore.OTSClient(
            OTS_ENDPOINT,
            OTS_ACCESS_KEY_ID,
            OTS_ACCESS_KEY_SECRET,
            instance_name=OTS_INSTANCE_NAME
        )
    return _ots_client


def _default_currency_for_exchange(exchange):
    normalized = str(exchange or '').upper()
    if 'NASDAQ' in normalized or 'NYSE' in normalized or normalized == 'US':
        return 'USD'
    return 'CNY'


def _default_locale_for_exchange(exchange):
    normalized = str(exchange or '').upper()
    if 'NASDAQ' in normalized or 'NYSE' in normalized or normalized == 'US':
        return 'en-US'
    return 'zh-CN'


def _default_country_for_exchange(exchange):
    normalized = str(exchange or '').upper()
    if 'NASDAQ' in normalized or 'NYSE' in normalized or normalized == 'US':
        return 'US'
    return 'CN'


def _normalize_asset_payload(data, asset_id=None):
    return {
        'id': asset_id or data.get('asset_id') or data.get('id') or str(uuid.uuid4()),
        'name': data.get('name', ''),
        'type': data.get('type', 'cash'),
        'balance': float(data.get('balance') or data.get('value') or 0),
        'currency': data.get('currency', 'CNY'),
        'locale': data.get('locale', 'zh-CN'),
        'countryCode': data.get('countryCode', 'CN'),
        'description': data.get('description'),
        'createdAt': data.get('createdAt', data.get('purchase_date', int(time.time() * 1000))),
        'syncStatus': data.get('syncStatus', 'synced'),
    }


def _normalize_stock_position_payload(data, position_id=None):
    exchange = data.get('exchange', '')
    return {
        'id': position_id or data.get('position_id') or data.get('id') or str(uuid.uuid4()),
        'assetType': data.get('assetType', 'stock'),
        'code': data.get('code', ''),
        'name': data.get('name', ''),
        'exchange': exchange,
        'marketCurrency': data.get('marketCurrency', _default_currency_for_exchange(exchange)),
        'locale': data.get('locale', _default_locale_for_exchange(exchange)),
        'countryCode': data.get('countryCode', _default_country_for_exchange(exchange)),
        'quantity': int(data.get('quantity', 0) or 0),
        'costPrice': data.get('costPrice'),
        'latestPrice': data.get('latestPrice'),
        'changePercent': data.get('changePercent'),
        'quoteUpdatedAt': data.get('quoteUpdatedAt'),
        'quoteStatus': data.get('quoteStatus', 'loading'),
        'createdAt': data.get('createdAt', datetime.now().isoformat()),
        'updatedAt': data.get('updatedAt', datetime.now().isoformat()),
    }

def _ots_get_entries(user_phone):
    try:
        import tablestore
        client = _get_ots_client()
        consumed, next_start, rows, next_token = client.get_range(
            OTS_TABLE,
            tablestore.Direction.FORWARD,
            [['user_phone', user_phone], ['entry_id', '']],
            [['user_phone', user_phone], ['entry_id', tablestore.INF_MAX]],
            limit=1000
        )
        entries = []
        for row in rows:
            attrs = {}
            for col in row.attribute_columns:
                attrs[col[0]] = col[1]
            attrs['id'] = row.primary_key[1][1]
            attrs['entry_id'] = row.primary_key[1][1]
            entries.append(attrs)
        return entries
    except Exception as e:
        print(f'[OTS Error] get_entries: {e}')
        traceback.print_exc()
        return []

def _ots_add_entry(user_phone, entry):
    try:
        import tablestore
        client = _get_ots_client()
        primary_key = [
            ['user_phone', user_phone],
            ['entry_id', entry['id']]
        ]
        attribute_columns = [
            ['date', entry['date']],
            ['createdAt', entry['createdAt']],
            ['amount', entry['amount']],
            ['type', entry['type']],
            ['category', entry['category']],
            ['description', entry['description']],
            ['syncStatus', entry['syncStatus']]
        ]
        row = tablestore.Row(primary_key, attribute_columns)
        consumed, next_token = client.put_row(
            OTS_TABLE, row,
            condition=tablestore.Condition('IGNORE')
        )
        return True
    except Exception as e:
        print(f'[OTS Error] add_entry: {repr(e)}')
        traceback.print_exc()
        return False

def _ots_update_entry(user_phone, entry_id, data):
    try:
        import tablestore
        client = _get_ots_client()
        # 先读取原有数据
        existing = None
        try:
            consumed, next_start, rows, next_token = client.get_range(
                OTS_TABLE,
                tablestore.Direction.FORWARD,
                [['user_phone', user_phone], ['entry_id', entry_id]],
                [['user_phone', user_phone], ['entry_id', entry_id]],
                limit=1
            )
            if rows:
                existing = {}
                for col in rows[0].attribute_columns:
                    existing[col[0]] = col[1]
        except:
            pass
        if existing:
            for k in ['date', 'createdAt', 'amount', 'type', 'category', 'description']:
                if k in data:
                    existing[k] = data[k]
            existing['syncStatus'] = data.get('syncStatus', 'synced')
        else:
            existing = data
        existing['id'] = entry_id
        client.delete_row(
            OTS_TABLE,
            tablestore.Row([['user_phone', user_phone], ['entry_id', entry_id]], []),
            condition=tablestore.Condition('EXPECT_EXIST')
        )
        return _ots_add_entry(user_phone, existing)
    except Exception as e:
        print(f'[OTS Error] update_entry: {e}')
        traceback.print_exc()
        return False

def _ots_delete_entry(user_phone, entry_id):
    try:
        import tablestore
        client = _get_ots_client()
        consumed, next_token = client.delete_row(
            OTS_TABLE,
            tablestore.Row([['user_phone', user_phone], ['entry_id', entry_id]], []),
            condition=tablestore.Condition('EXPECT_EXIST')
        )
        return True
    except Exception as e:
        print(f'[OTS Error] delete_entry: {e}')
        traceback.print_exc()
        return False

# ─── 资产 OTS 操作 ────────────────────────────────────────
ASSET_TABLE = os.environ.get('ASSET_TABLE', 'asset_items')


def _ots_get_stock_positions(user_phone):
    """获取指定用户的所有股票持仓"""
    try:
        import tablestore
        client = _get_ots_client()
        consumed, next_start, rows, next_token = client.get_range(
            STOCK_POSITIONS_TABLE,
            tablestore.Direction.FORWARD,
            [['user_phone', user_phone], ['position_id', '']],
            [['user_phone', user_phone], ['position_id', tablestore.INF_MAX]],
            limit=1000
        )
        positions = []
        for row in rows:
            attrs = {}
            for col in row.attribute_columns:
                attrs[col[0]] = col[1]
            attrs['id'] = row.primary_key[1][1]
            attrs['position_id'] = row.primary_key[1][1]
            positions.append(attrs)
        return positions
    except Exception as e:
        print(f'[OTS Error] get_stock_positions: {e}')
        traceback.print_exc()
        return []

def _ots_add_stock_position(user_phone, position):
    """添加股票持仓到 OTS"""
    try:
        import tablestore
        client = _get_ots_client()
        position = _normalize_stock_position_payload(position, position.get('id'))
        primary_key = [
            ['user_phone', user_phone],
            ['position_id', position['id']]
        ]
        attribute_columns = [
            ['assetType', position.get('assetType', 'stock')],
            ['code', position.get('code', '')],
            ['name', position.get('name', '')],
            ['exchange', position.get('exchange', '')],
            ['marketCurrency', position.get('marketCurrency')],
            ['locale', position.get('locale')],
            ['countryCode', position.get('countryCode')],
            ['quantity', int(position.get('quantity', 0))],
            ['costPrice', position.get('costPrice')],
            ['latestPrice', position.get('latestPrice')],
            ['changePercent', position.get('changePercent')],
            ['quoteUpdatedAt', position.get('quoteUpdatedAt')],
            ['quoteStatus', position.get('quoteStatus', 'loading')],
            ['createdAt', position.get('createdAt', datetime.now().isoformat())],
            ['updatedAt', position.get('updatedAt', datetime.now().isoformat())],
        ]
        attribute_columns = [col for col in attribute_columns if col[1] is not None]
        row = tablestore.Row(primary_key, attribute_columns)
        consumed, next_token = client.put_row(
            STOCK_POSITIONS_TABLE, row,
            condition=tablestore.Condition('IGNORE')
        )
        return True
    except Exception as e:
        print(f'[OTS Error] add_stock_position: {repr(e)}')
        traceback.print_exc()
        return False

def _ots_update_stock_position(user_phone, position_id, data):
    """更新 OTS 中的股票持仓"""
    try:
        import tablestore
        client = _get_ots_client()
        existing = None
        try:
            consumed, next_start, rows, next_token = client.get_range(
                STOCK_POSITIONS_TABLE,
                tablestore.Direction.FORWARD,
                [['user_phone', user_phone], ['position_id', position_id]],
                [['user_phone', user_phone], ['position_id', position_id]],
                limit=1
            )
            if rows:
                existing = {}
                for col in rows[0].attribute_columns:
                    existing[col[0]] = col[1]
        except:
            pass
        if existing:
            for k in ['assetType', 'code', 'name', 'exchange', 'marketCurrency', 'locale', 'countryCode', 'quantity', 'costPrice', 'latestPrice', 'changePercent', 'quoteUpdatedAt', 'quoteStatus', 'createdAt', 'updatedAt']:
                if k in data:
                    existing[k] = data[k]
        else:
            existing = data
        existing = _normalize_stock_position_payload(existing, position_id)
        existing['updatedAt'] = data.get('updatedAt', existing.get('updatedAt', datetime.now().isoformat()))
        client.delete_row(
            STOCK_POSITIONS_TABLE,
            tablestore.Row([['user_phone', user_phone], ['position_id', position_id]], []),
            condition=tablestore.Condition('EXPECT_EXIST')
        )
        return _ots_add_stock_position(user_phone, existing)
    except Exception as e:
        print(f'[OTS Error] update_stock_position: {e}')
        traceback.print_exc()
        return False

def _ots_delete_stock_position(user_phone, position_id):
    """从 OTS 删除股票持仓"""
    try:
        import tablestore
        client = _get_ots_client()
        consumed, next_token = client.delete_row(
            STOCK_POSITIONS_TABLE,
            tablestore.Row([['user_phone', user_phone], ['position_id', position_id]], []),
            condition=tablestore.Condition('EXPECT_EXIST')
        )
        return True
    except Exception as e:
        print(f'[OTS Error] delete_stock_position: {e}')
        traceback.print_exc()
        return False

def _ots_get_assets(user_phone):
    """获取指定用户的所有资产账户"""
    try:
        import tablestore
        client = _get_ots_client()
        consumed, next_start, rows, next_token = client.get_range(
            ASSET_TABLE,
            tablestore.Direction.FORWARD,
            [['user_phone', user_phone], ['asset_id', '']],
            [['user_phone', user_phone], ['asset_id', tablestore.INF_MAX]],
            limit=1000
        )
        assets = []
        for row in rows:
            attrs = {}
            for col in row.attribute_columns:
                attrs[col[0]] = col[1]
            attrs['id'] = row.primary_key[1][1]
            attrs['asset_id'] = row.primary_key[1][1]
            assets.append(attrs)
        return assets
    except Exception as e:
        print(f'[OTS Error] get_assets: {e}')
        traceback.print_exc()
        return []

def _ots_add_asset(user_phone, asset):
    """添加资产到 OTS"""
    try:
        import tablestore
        client = _get_ots_client()
        asset = _normalize_asset_payload(asset, asset.get('id'))
        primary_key = [
            ['user_phone', user_phone],
            ['asset_id', asset['id']]
        ]
        attribute_columns = [
            ['name', asset['name']],
            ['type', asset['type']],
            ['balance', asset['balance']],
            ['currency', asset.get('currency', 'CNY')],
            ['locale', asset.get('locale', 'zh-CN')],
            ['countryCode', asset.get('countryCode', 'CN')],
            ['description', asset.get('description')],
            ['createdAt', asset.get('createdAt', 0)],
            ['syncStatus', asset.get('syncStatus', 'synced')]
        ]
        attribute_columns = [col for col in attribute_columns if col[1] is not None]
        row = tablestore.Row(primary_key, attribute_columns)
        consumed, next_token = client.put_row(
            ASSET_TABLE, row,
            condition=tablestore.Condition('IGNORE')
        )
        return True
    except Exception as e:
        print(f'[OTS Error] add_asset: {repr(e)}')
        traceback.print_exc()
        return False

def _ots_update_asset(user_phone, asset_id, data):
    """更新 OTS 中的资产"""
    try:
        import tablestore
        client = _get_ots_client()
        # 先读取
        existing = None
        try:
            consumed, next_start, rows, next_token = client.get_range(
                ASSET_TABLE,
                tablestore.Direction.FORWARD,
                [['user_phone', user_phone], ['asset_id', asset_id]],
                [['user_phone', user_phone], ['asset_id', asset_id]],
                limit=1
            )
            if rows:
                existing = {}
                for col in rows[0].attribute_columns:
                    existing[col[0]] = col[1]
        except:
            pass
        if existing:
            for k in ['name', 'type', 'balance', 'currency', 'locale', 'countryCode', 'description', 'createdAt']:
                if k in data:
                    existing[k] = data[k]
            existing['syncStatus'] = data.get('syncStatus', 'synced')
        else:
            existing = data
        existing = _normalize_asset_payload(existing, asset_id)
        client.delete_row(
            ASSET_TABLE,
            tablestore.Row([['user_phone', user_phone], ['asset_id', asset_id]], []),
            condition=tablestore.Condition('EXPECT_EXIST')
        )
        return _ots_add_asset(user_phone, existing)
    except Exception as e:
        print(f'[OTS Error] update_asset: {e}')
        traceback.print_exc()
        return False

def _ots_delete_asset(user_phone, asset_id):
    """从 OTS 删除资产"""
    try:
        import tablestore
        client = _get_ots_client()
        consumed, next_token = client.delete_row(
            ASSET_TABLE,
            tablestore.Row([['user_phone', user_phone], ['asset_id', asset_id]], []),
            condition=tablestore.Condition('EXPECT_EXIST')
        )
        return True
    except Exception as e:
        print(f'[OTS Error] delete_asset: {e}')
        traceback.print_exc()
        return False

def _load_json(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {}


def _save_json(path, data):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _load():
    return _load_json(DB_FILE)


def _save(entries):
    _save_json(DB_FILE, entries)


def _load_sms_codes():
    return _load_json(SMS_CODES_FILE)


def _save_sms_codes(codes):
    _save_json(SMS_CODES_FILE, codes)


# ─── 阿里云 SMS 签名生成 ──────────────────────────────
def _aliyun_signature(method, path, queries):
    """生成阿里云 HMAC-SHA1 签名"""
    sorted_q = sorted(queries.items())
    query_str = '&'.join(f'{k}={urllib.parse.quote(str(v), safe="~")}' for k, v in sorted_q)
    string_to_sign = f'{method}&%2F&{urllib.parse.quote(query_str, safe="")}'
    key = f'{ALIYUN_ACCESS_KEY_SECRET}&'
    return base64.b64encode(
        hmac.new(key.encode('utf-8'), string_to_sign.encode('utf-8'), hashlib.sha1).digest()
    ).decode('utf-8')


def _send_sms_via_aliyun(phone, code):
    """调阿里云 SendSms API"""
    if not ALIYUN_ACCESS_KEY_ID or not ALIYUN_ACCESS_KEY_SECRET or not ALIYUN_SMS_TEMPLATE_CODE:
        return {'code': 'ConfigMissing', 'message': 'SMS not configured'}

    import urllib.request

    params = {
        'AccessKeyId': ALIYUN_ACCESS_KEY_ID,
        'SignatureMethod': 'HMAC-SHA1',
        'SignatureVersion': '1.0',
        'SignatureNonce': str(uuid.uuid4()),
        'Timestamp': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
        'Format': 'JSON',
        'Action': 'SendSms',
        'Version': '2017-05-25',
        'RegionId': SMS_REGION,
        'PhoneNumbers': phone,
        'SignName': ALIYUN_SMS_SIGN_NAME,
        'TemplateCode': ALIYUN_SMS_TEMPLATE_CODE,
        'TemplateParam': json.dumps({'code': code}),
    }

    signature = _aliyun_signature('GET', '/', params)
    params['Signature'] = signature

    url = 'https://dysmsapi.aliyuncs.com/?' + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception as e:
        return {'code': 'NetworkError', 'message': str(e)}


def _generate_code():
    return ''.join(random.choices(string.digits, k=6))


# ─── 融合认证：获取 authToken ────────────────────────
def _get_fusion_auth_token(app_id, app_key):
    """调阿里云 GetFusionAuthToken 接口，换取认证Token"""
    import urllib.request

    params = {
        'AccessKeyId': ALIYUN_ACCESS_KEY_ID,
        'SignatureMethod': 'HMAC-SHA1',
        'SignatureVersion': '1.0',
        'SignatureNonce': str(uuid.uuid4()),
        'Timestamp': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
        'Format': 'JSON',
        'Action': 'GetFusionAuthToken',
        'Version': '2017-05-25',
        'RegionId': 'cn-hangzhou',
        'AppId': app_id,
        'AppKey': app_key,
    }

    signature = _aliyun_signature('GET', '/', params)
    params['Signature'] = signature

    url = 'https://dypnsapi.aliyuncs.com/?' + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            result = json.loads(resp.read().decode('utf-8'))
            if result.get('Code') == 'OK' and result.get('Token'):
                return {'success': True, 'authToken': result['Token']['Token'], 'accessCode': result['Token'].get('AccessCode')}
            else:
                return {'success': False, 'error': result.get('Message', 'Unknown error')}
    except Exception as e:
        return {'success': False, 'error': str(e)}


def _verify_mobile(mask_token, app_id, app_key):
    """调阿里云 VerifyMobile 接口，通过 maskToken 换取真实手机号"""
    import urllib.request

    params = {
        'AccessKeyId': ALIYUN_ACCESS_KEY_ID,
        'SignatureMethod': 'HMAC-SHA1',
        'SignatureVersion': '1.0',
        'SignatureNonce': str(uuid.uuid4()),
        'Timestamp': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
        'Format': 'JSON',
        'Action': 'VerifyMobile',
        'Version': '2017-05-25',
        'RegionId': 'cn-hangzhou',
        'AppId': app_id,
        'AppKey': app_key,
        'MaskToken': mask_token,
    }

    signature = _aliyun_signature('GET', '/', params)
    params['Signature'] = signature

    url = 'https://dypnsapi.aliyuncs.com/?' + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            result = json.loads(resp.read().decode('utf-8'))
            if result.get('Code') == 'OK':
                phone = result.get('PhoneNumber', '')
                return {'success': True, 'phone': phone}
            else:
                return {'success': False, 'error': result.get('Message', 'Unknown error')}
    except Exception as e:
        return {'success': False, 'error': str(e)}


# ─── VIP OTS 操作 ────────────────────────────────────

def _ots_get_vip_profile(user_phone):
    try:
        import tablestore
        client = _get_ots_client()
        consumed, next_start, rows, next_token = client.get_range(
            VIP_TABLE,
            tablestore.Direction.FORWARD,
            [['user_phone', user_phone], ['profile_key', '']],
            [['user_phone', user_phone], ['profile_key', tablestore.INF_MAX]],
            limit=1
        )
        if not rows:
            return {}
        attrs = {}
        for col in rows[0].attribute_columns:
            attrs[col[0]] = col[1]
        return attrs
    except Exception as e:
        print(f'[OTS Error] get_vip_profile: {e}')
        traceback.print_exc()
        return {}


def _ots_put_vip_profile(user_phone, profile):
    try:
        import tablestore
        client = _get_ots_client()
        primary_key = [
            ['user_phone', user_phone],
            ['profile_key', 'vip']
        ]
        attribute_columns = [
            ['vip_type', profile.get('vip_type', '')],
            ['vip_expire_ms', int(profile.get('vip_expire_ms', 0) or 0)],
            ['vip_environment', profile.get('vip_environment', 'unknown')],
            ['updated_at', profile.get('updated_at', datetime.now().isoformat())],
        ]
        row = tablestore.Row(primary_key, attribute_columns)
        client.put_row(
            VIP_TABLE,
            row,
            condition=tablestore.Condition('IGNORE')
        )
        return True
    except Exception as e:
        print(f'[OTS Error] put_vip_profile: {e}')
        traceback.print_exc()
        return False


def _ots_delete_vip_profile(user_phone):
    try:
        import tablestore
        client = _get_ots_client()
        client.delete_row(
            VIP_TABLE,
            tablestore.Row([['user_phone', user_phone], ['profile_key', 'vip']], []),
            condition=tablestore.Condition('IGNORE')
        )
        return True
    except Exception as e:
        print(f'[OTS Error] delete_vip_profile: {e}')
        traceback.print_exc()
        return False


def _is_vip_expired(expire_ms):
    if not expire_ms or int(expire_ms) <= 0:
        return True
    return int(time.time() * 1000) > int(expire_ms)


def _vip_environment_priority(environment):
    if environment == 'production':
        return 3
    if environment == 'unknown':
        return 2
    if environment == 'sandbox':
        return 1
    return 0


def _verify_receipt_with_apple(receipt_data):
    if not receipt_data:
        return None
    if not APP_STORE_SHARED_SECRET:
        print('[VIP] APP_STORE_SHARED_SECRET not configured, skip Apple verify')
        return None

    print(f'[VIP] Apple verify start, receipt_len={len(receipt_data)}')

    payload = json.dumps({
        'receipt-data': receipt_data,
        'password': APP_STORE_SHARED_SECRET,
        'exclude-old-transactions': True,
    }).encode('utf-8')

    def _post(url):
        import urllib.request
        req = urllib.request.Request(
            url,
            data=payload,
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode('utf-8'))

    try:
        data = _post(APPLE_VERIFY_URL)
        status = data.get('status', -1)
        print(f'[VIP] Apple verify production status={status}')
        if status == 0:
            return {
                'environment': 'production',
                'receipt_info': data.get('latest_receipt_info') or data.get('receipt')
            }
        if status == 21007:
            data = _post(SANDBOX_VERIFY_URL)
            status = data.get('status', -1)
            print(f'[VIP] Apple verify sandbox status={status}')
            if status == 0:
                return {
                    'environment': 'sandbox',
                    'receipt_info': data.get('latest_receipt_info') or data.get('receipt')
                }
        print(f'[VIP] Apple verify unresolved status={status}')
    except Exception as e:
        print(f'[VIP] Apple verify error: {e}')
    return None


def _apple_subscription_expire_ms(receipt_info):
    if not receipt_info:
        return 0
    if isinstance(receipt_info, list):
        receipt_info = receipt_info[-1] if receipt_info else {}

    expires_date_ms = receipt_info.get('expires_date_ms') or receipt_info.get('subscription-expire-date-ms')
    if expires_date_ms:
        try:
            return int(expires_date_ms)
        except Exception:
            pass
    return 0


# ─── HTTP Handler ────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    def _get_user_phone(self):
        """从请求头获取用户手机号"""
        return self.headers.get('X-User-Phone', '')

    def do_GET(self):
        if self.path == '/health':
            # 健康检查，测试 OTS 连接
            try:
                import tablestore
                # 测试 1：环境变量
                env_check = {
                    'OTS_INSTANCE_NAME': OTS_INSTANCE_NAME,
                    'OTS_REGION': OTS_REGION,
                    'OTS_ENDPOINT': OTS_ENDPOINT,
                    'OTS_TABLE': OTS_TABLE,
                    'ASSET_TABLE': ASSET_TABLE,
                    'VIP_TABLE': VIP_TABLE,
                    'OTS_ACCESS_KEY_ID_LEN': len(OTS_ACCESS_KEY_ID),
                    'OTS_ACCESS_KEY_SECRET_LEN': len(OTS_ACCESS_KEY_SECRET),
                }
                # 测试 2：OTS 客户端初始化
                client = _get_ots_client()
                env_check['ots_client_init'] = True
                # 不再尝试 get_range，避免导入问题
                self._respond(200, {'status': 'ok', 'env': env_check})
            except Exception as e:
                self._respond(500, {'status': 'error', 'error': str(e), 'traceback': traceback.format_exc()})
        elif self.path.startswith('/entries'):
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return
            entries = _ots_get_entries(user_phone)
            self._respond(200, {'entries': entries, 'total': len(entries)})
        elif self.path.startswith('/assets'):
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return
            assets = _ots_get_assets(user_phone)
            self._respond(200, {'assets': assets})
        elif self.path.startswith('/stock_positions'):
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return
            positions = _ots_get_stock_positions(user_phone)
            self._respond(200, {'stock_positions': positions, 'total': len(positions)})
        elif self.path.startswith('/vip'):
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return
            profile = _ots_get_vip_profile(user_phone)
            self._respond(200, {'profile': profile})
        else:
            self._respond(404, {'error': 'Not found'})

    def do_POST(self):
        if self.path == '/entries':
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return

            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body) if body else {}
            now_ms = int(time.time() * 1000)
            # 兼容 entry_id 和 id 两种字段
            entry_id = data.get('entry_id') or data.get('id') or str(uuid.uuid4())
            entry = {
                'id': entry_id,
                'amount': float(data.get('amount', 0)),
                'type': data.get('type', 'expense'),
                'category': data.get('category', 'other'),
                'description': data.get('description', ''),
                'date': data.get('date', now_ms),
                'createdAt': data.get('createdAt', now_ms),
                'syncStatus': 'synced',
            }
            try:
                success = _ots_add_entry(user_phone, entry)
                if success:
                    self._respond(200, {'entry': entry})
                else:
                    self._respond(500, {'error': 'OTS write failed - check logs'})
            except Exception as e:
                self._respond(500, {'error': f'OTS exception: {str(e)}', 'traceback': traceback.format_exc()})

        elif self.path == '/assets':
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body) if body else {}
            asset = _normalize_asset_payload(data)
            try:
                success = _ots_add_asset(user_phone, asset)
                if success:
                    self._respond(200, {'asset': asset})
                else:
                    self._respond(500, {'error': 'OTS write failed'})
            except Exception as e:
                self._respond(500, {'error': f'OTS exception: {str(e)}', 'traceback': traceback.format_exc()})


        elif self.path == '/stock_positions':
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body) if body else {}
            position = _normalize_stock_position_payload(data)
            try:
                success = _ots_add_stock_position(user_phone, position)
                if success:
                    self._respond(200, {'stock_position': position})
                else:
                    self._respond(500, {'error': 'OTS write failed'})
            except Exception as e:
                self._respond(500, {'error': f'OTS exception: {str(e)}', 'traceback': traceback.format_exc()})

        elif self.path == '/sms/send':
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body) if body else {}
            phone = data.get('phone', '').strip()
            if not phone or len(phone) < 11:
                self._respond(400, {'error': 'Invalid phone number'})
                return

            code = _generate_code()
            expire = int(time.time()) + 300  # 5分钟有效

            codes = _load_sms_codes()
            codes[phone] = {'code': code, 'expire': expire}
            _save_sms_codes(codes)

            # 真实发送（未配置时返回模拟成功）
            if ALIYUN_SMS_SIGN_NAME and ALIYUN_SMS_TEMPLATE_CODE:
                result = _send_sms_via_aliyun(phone, code)
                if result.get('Code') == 'OK':
                    self._respond(200, {'message': 'SMS sent', 'simulated': False})
                else:
                    self._respond(200, {'message': 'SMS API error', 'detail': result, 'simulated': False})
            else:
                # 模拟模式（未配置阿里云 SMS 时）
                print(f'[SMS Mock] phone={phone} code={code}')
                self._respond(200, {'message': 'SMS sent (simulated)', 'simulated': True})

        elif self.path == '/sms/verify':
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body) if body else {}
            phone = data.get('phone', '').strip()
            code = data.get('code', '').strip()

            codes = _load_sms_codes()
            record = codes.get(phone)
            if not record:
                self._respond(200, {'valid': False, 'reason': 'No code sent'})
                return
            if int(time.time()) > record['expire']:
                self._respond(200, {'valid': False, 'reason': 'Code expired'})
                return
            if record['code'] != code:
                self._respond(200, {'valid': False, 'reason': 'Wrong code'})
                return

            # 验证通过，删除验证码
            del codes[phone]
            _save_sms_codes(codes)
            self._respond(200, {'valid': True})

        elif self.path == '/auth/token':
            # 获取融合认证 authToken（供 iOS SDK 使用）
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body) if body else {}
            app_id = data.get('appId', '').strip()
            app_key = data.get('appKey', '').strip()

            if not app_id or not app_key:
                self._respond(400, {'success': False, 'error': 'Missing appId or appKey'})
                return

            result = _get_fusion_auth_token(app_id, app_key)
            if result.get('success'):
                self._respond(200, {'success': True, 'authToken': result['authToken']})
            else:
                self._respond(200, {'success': False, 'error': result.get('error', 'Unknown error')})

        elif self.path == '/auth/verify':
            # 通过 maskToken 换取真实手机号
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body) if body else {}
            mask_token = data.get('maskToken', '').strip()
            app_id = data.get('appId', '').strip()
            app_key = data.get('appKey', '').strip()

            if not mask_token:
                self._respond(400, {'success': False, 'error': 'Missing maskToken'})
                return

            # Use provided appId/appKey or fallback to env
            if not app_id:
                app_id = os.environ.get('ALIYUN_AUTH_APP_ID', '')
            if not app_key:
                app_key = os.environ.get('ALIYUN_AUTH_APP_KEY', '')

            result = _verify_mobile(mask_token, app_id, app_key)
            if result.get('success'):
                self._respond(200, {'success': True, 'phone': result.get('phone', '')})
            else:
                self._respond(200, {'success': False, 'error': result.get('error', 'Unknown error')})

        elif self.path == '/vip/sync':
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return

            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body) if body else {}

            vip_type = data.get('vip_type', '')
            vip_expire_ms = int(data.get('vip_expire_ms', 0) or 0)
            receipt_data = data.get('receipt_data')
            incoming_environment = data.get('vip_environment', 'unknown') or 'unknown'
            existing_profile = _ots_get_vip_profile(user_phone)
            existing_environment = existing_profile.get('vip_environment', 'unknown')

            print(
                f'[VIP] /vip/sync user={user_phone} vip_type={vip_type} expire_ms={vip_expire_ms} '
                f'incoming_env={incoming_environment} existing_env={existing_environment} '
                f'has_receipt={bool(receipt_data)}'
            )

            if receipt_data:
                receipt_result = _verify_receipt_with_apple(receipt_data)
                if receipt_result is not None:
                    incoming_environment = receipt_result.get('environment', 'unknown')
                    receipt_info = receipt_result.get('receipt_info')
                    apple_expire_ms = _apple_subscription_expire_ms(receipt_info)
                    if apple_expire_ms > 0:
                        vip_expire_ms = apple_expire_ms
                        product_id = ''
                        if isinstance(receipt_info, dict):
                            product_id = receipt_info.get('product_id', '')
                        if 'year' in product_id:
                            vip_type = 'yearly'
                        elif 'mon' in product_id:
                            vip_type = 'monthly'
                else:
                    print('[VIP] receipt verify returned None, keeping incoming environment')

            # 保护规则 1：sandbox / unknown 不允许覆盖更高优先级记录
            if existing_profile and _vip_environment_priority(existing_environment) > _vip_environment_priority(incoming_environment):
                print(f'[VIP] ignore lower-priority profile: incoming={incoming_environment} existing={existing_environment}')
                self._respond(200, {'profile': existing_profile})
                return

            # 保护规则 2：只要现有档案已存在，未经 Apple 验证出的 unknown 一律不允许覆盖。
            # 这样可以挡住 TestFlight/restore 本地错误日期在 receipt 未校验成功时再次把云端改坏。
            if existing_profile and incoming_environment == 'unknown' and existing_environment in ('unknown', 'production'):
                print(f'[VIP] ignore unknown overwrite: incoming={incoming_environment} existing={existing_environment}')
                self._respond(200, {'profile': existing_profile})
                return

            if vip_expire_ms > 0 and _is_vip_expired(vip_expire_ms):
                self._respond(403, {
                    'error': 'subscription_expired',
                    'message': '会员已过期，拒绝写入过期状态'
                })
                return

            profile = {
                'vip_type': vip_type,
                'vip_expire_ms': vip_expire_ms,
                'vip_environment': incoming_environment,
                'updated_at': datetime.now().isoformat(),
            }

            success = _ots_put_vip_profile(user_phone, profile)
            if success:
                print(f'[VIP] /vip/sync saved profile={profile}')
                self._respond(200, {'profile': profile})
            else:
                self._respond(500, {'error': 'OTS vip write failed'})

        else:
            self._respond(404, {'error': 'Not found'})

    def do_PUT(self):
        if self.path.startswith('/entries/'):
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return

            entry_id = self.path.split('/')[-1]
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body) if body else {}
            success = _ots_update_entry(user_phone, entry_id, data)
            if success:
                self._respond(200, {'message': 'Entry updated', 'entry': data})
            else:
                self._respond(404, {'error': 'Entry not found or update failed'})
        elif self.path.startswith('/assets/'):
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return
            asset_id = self.path.split('/')[-1]
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body) if body else {}
            success = _ots_update_asset(user_phone, asset_id, data)
            if success:
                self._respond(200, {'message': 'Asset updated', 'asset': data})
            else:
                self._respond(404, {'error': 'Asset not found or update failed'})

        elif self.path == '/stock_positions':
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body) if body else {}
            positions = data.get('stock_positions', [])
            if not isinstance(positions, list):
                self._respond(400, {'error': 'stock_positions must be a list'})
                return
            normalized = []
            for item in positions:
                pid = item.get('position_id') or item.get('id') or str(uuid.uuid4())
                item = _normalize_stock_position_payload(item, pid)
                ok = _ots_update_stock_position(user_phone, pid, item)
                if not ok:
                    ok = _ots_add_stock_position(user_phone, item)
                if not ok:
                    self._respond(500, {'error': f'Failed to sync stock position: {pid}'})
                    return
                normalized.append(item)
            self._respond(200, {'stock_positions': normalized})
        elif self.path.startswith('/stock_positions/'):
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return
            position_id = self.path.split('/')[-1]
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body) if body else {}
            success = _ots_update_stock_position(user_phone, position_id, data)
            if success:
                self._respond(200, {'message': 'Stock position updated', 'stock_position': data})
            else:
                self._respond(404, {'error': 'Stock position not found or update failed'})
        else:
            self._respond(404, {'error': 'Not found'})

    def do_DELETE(self):
        if self.path == '/account':
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return
            # 删除所有账单
            entries = _ots_get_entries(user_phone)
            for entry in entries:
                _ots_delete_entry(user_phone, entry['entry_id'])
            # 删除所有资产
            assets = _ots_get_assets(user_phone)
            for asset in assets:
                _ots_delete_asset(user_phone, asset['asset_id'])
            # 删除所有股票持仓
            positions = _ots_get_stock_positions(user_phone)
            for position in positions:
                _ots_delete_stock_position(user_phone, position['position_id'])
            _ots_delete_vip_profile(user_phone)
            self._respond(200, {'deleted': True, 'user_phone': user_phone})
        elif self.path.startswith('/entries/'):
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return

            entry_id = self.path.split('/')[-1]
            success = _ots_delete_entry(user_phone, entry_id)
            if success:
                self._respond(200, {'deleted': entry_id})
            else:
                self._respond(404, {'error': 'Entry not found or delete failed'})
        elif self.path.startswith('/assets/'):
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return
            asset_id = self.path.split('/')[-1]
            success = _ots_delete_asset(user_phone, asset_id)
            if success:
                self._respond(200, {'deleted': asset_id})
            else:
                self._respond(404, {'error': 'Asset not found or delete failed'})

        elif self.path.startswith('/stock_positions/'):
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return
            position_id = self.path.split('/')[-1]
            success = _ots_delete_stock_position(user_phone, position_id)
            if success:
                self._respond(200, {'deleted': position_id})
            else:
                self._respond(404, {'error': 'Stock position not found or delete failed'})
        else:
            self._respond(404, {'error': 'Not found'})

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-User-Phone')
        self.end_headers()

    def _respond(self, status, data):
        body = json.dumps(data, ensure_ascii=False)
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body.encode('utf-8'))

    def log_message(self, format, *args):
        print(f'[FC] {format % args}')


if __name__ == '__main__':
    port = int(os.environ.get('FC_FUNCTION_PORT', '9000'))
    server = HTTPServer(('', port), Handler)
    server.serve_forever()
