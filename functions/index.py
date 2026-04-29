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
import urllib.request
import traceback
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
import ssl

DB_FILE = '/tmp/entries.json'
SMS_CODES_FILE = '/tmp/sms_codes.json'

# ─── 短信配置（从环境变量读取）──────────────────────────
ALIYUN_ACCESS_KEY_ID     = os.environ.get('ALIYUN_ACCESS_KEY_ID', '')
ALIYUN_ACCESS_KEY_SECRET  = os.environ.get('ALIYUN_ACCESS_KEY_SECRET', '')
ALIYUN_SMS_SIGN_NAME     = os.environ.get('ALIYUN_SMS_SIGN_NAME', 'AI记账鸭')
ALIYUN_SMS_TEMPLATE_CODE = os.environ.get('ALIYUN_SMS_TEMPLATE_CODE', '')
SMS_REGION               = 'cn-hangzhou'

# ─── Apple 订阅校验配置 ─────────────────────────────
APP_STORE_SHARED_SECRET = os.environ.get('APP_STORE_SHARED_SECRET', '')
APPLE_VERIFY_URL = 'https://buy.itunes.apple.com/verifyReceipt'
SANDBOX_VERIFY_URL = 'https://sandbox.itunes.apple.com/verifyReceipt'
APP_STORE_BUNDLE_ID = os.environ.get('APP_STORE_BUNDLE_ID', 'com.phil.AIAccountant')
APP_STORE_SERVER_ISSUER_ID = os.environ.get('APP_STORE_SERVER_ISSUER_ID', '')
APP_STORE_SERVER_KEY_ID = os.environ.get('APP_STORE_SERVER_KEY_ID', '')
APP_STORE_SERVER_PRIVATE_KEY = os.environ.get('APP_STORE_SERVER_PRIVATE_KEY', '')
APP_STORE_SERVER_PRIVATE_KEY_PATH = os.environ.get('APP_STORE_SERVER_PRIVATE_KEY_PATH', '')
APP_STORE_SERVER_API_ENV = os.environ.get('APP_STORE_SERVER_API_ENV', 'production').lower()
APP_STORE_ROOT_CERT_PEM = os.environ.get('APP_STORE_ROOT_CERT_PEM', '')
APP_STORE_REQUIRE_TRUSTED_JWS = os.environ.get('APP_STORE_REQUIRE_TRUSTED_JWS', 'false').lower() == 'true'
APP_STORE_PRODUCTION_API = 'https://api.storekit.itunes.apple.com'
APP_STORE_SANDBOX_API = 'https://api.storekit-sandbox.itunes.apple.com'

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
            ['vip_verify_status', str(profile.get('vip_verify_status', ''))],
            ['vip_verify_error', str(profile.get('vip_verify_error', ''))],
            ['product_id', str(profile.get('product_id', ''))],
            ['transaction_id', str(profile.get('transaction_id', ''))],
            ['original_transaction_id', str(profile.get('original_transaction_id', ''))],
            ['app_account_token', str(profile.get('app_account_token', ''))],
            ['purchase_ms', int(profile.get('purchase_ms', 0) or 0)],
            ['revocation_ms', int(profile.get('revocation_ms', 0) or 0)],
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


def _ots_find_vip_user_by_subscription(app_account_token='', transaction_id='', original_transaction_id=''):
    """Best-effort mapping from an Apple notification back to the app user.

    The VIP table is tiny today and keyed by user_phone, so a bounded scan is
    acceptable. If ads/subscriptions scale up, replace this with an OTS secondary
    index on app_account_token/original_transaction_id.
    """
    try:
        import tablestore
        client = _get_ots_client()
        _, _, rows, _ = client.get_range(
            VIP_TABLE,
            tablestore.Direction.FORWARD,
            [['user_phone', ''], ['profile_key', '']],
            [['user_phone', tablestore.INF_MAX], ['profile_key', tablestore.INF_MAX]],
            limit=1000
        )
        for row in rows:
            attrs = {col[0]: col[1] for col in row.attribute_columns}
            primary_key = dict(row.primary_key)
            user_phone = primary_key.get('user_phone', '')
            if not user_phone:
                continue
            if app_account_token and attrs.get('app_account_token') == app_account_token:
                return user_phone
            if original_transaction_id and attrs.get('original_transaction_id') == original_transaction_id:
                return user_phone
            if transaction_id and attrs.get('transaction_id') == transaction_id:
                return user_phone
    except Exception as e:
        print(f'[OTS Error] find_vip_user_by_subscription: {e}')
        traceback.print_exc()
    return ''


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
    if environment == 'sandbox':
        return 2
    if environment == 'unknown':
        return 1
    return 0


def _b64url_decode(raw):
    raw = raw.encode('utf-8') if isinstance(raw, str) else raw
    raw += b'=' * (-len(raw) % 4)
    return base64.urlsafe_b64decode(raw)


def _b64url_encode(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b'=').decode('utf-8')


def _crypto_imports():
    try:
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import (
            decode_dss_signature,
            encode_dss_signature,
        )
        return {
            'x509': x509,
            'hashes': hashes,
            'serialization': serialization,
            'ec': ec,
            'decode_dss_signature': decode_dss_signature,
            'encode_dss_signature': encode_dss_signature,
        }
    except Exception as e:
        print(f'[AppStore] cryptography unavailable: {e}')
        return None


def _load_app_store_private_key():
    crypto = _crypto_imports()
    if crypto is None:
        return None

    key_pem = APP_STORE_SERVER_PRIVATE_KEY
    if not key_pem and APP_STORE_SERVER_PRIVATE_KEY_PATH:
        try:
            with open(APP_STORE_SERVER_PRIVATE_KEY_PATH, 'r', encoding='utf-8') as f:
                key_pem = f.read()
        except Exception as e:
            print(f'[AppStore] private key path read failed: {e}')
            return None

    if not key_pem:
        return None

    key_pem = key_pem.replace('\\n', '\n').strip()
    try:
        return crypto['serialization'].load_pem_private_key(
            key_pem.encode('utf-8'),
            password=None,
        )
    except Exception as e:
        print(f'[AppStore] private key load failed: {e}')
        return None


def _is_app_store_server_api_configured():
    return bool(
        APP_STORE_SERVER_ISSUER_ID
        and APP_STORE_SERVER_KEY_ID
        and (APP_STORE_SERVER_PRIVATE_KEY or APP_STORE_SERVER_PRIVATE_KEY_PATH)
    )


def _make_app_store_server_jwt():
    crypto = _crypto_imports()
    private_key = _load_app_store_private_key()
    if crypto is None or private_key is None:
        return None

    now = int(time.time())
    header = {
        'alg': 'ES256',
        'kid': APP_STORE_SERVER_KEY_ID,
        'typ': 'JWT',
    }
    payload = {
        'iss': APP_STORE_SERVER_ISSUER_ID,
        'iat': now,
        'exp': now + 20 * 60,
        'aud': 'appstoreconnect-v1',
        'bid': APP_STORE_BUNDLE_ID,
    }
    signing_input = '.'.join([
        _b64url_encode(json.dumps(header, separators=(',', ':')).encode('utf-8')),
        _b64url_encode(json.dumps(payload, separators=(',', ':')).encode('utf-8')),
    ]).encode('utf-8')

    der_sig = private_key.sign(signing_input, crypto['ec'].ECDSA(crypto['hashes'].SHA256()))
    r, s = crypto['decode_dss_signature'](der_sig)
    raw_sig = r.to_bytes(32, 'big') + s.to_bytes(32, 'big')
    return signing_input.decode('utf-8') + '.' + _b64url_encode(raw_sig)


def _verify_cert_signed_by(child_cert, issuer_cert, crypto):
    try:
        issuer_public_key = issuer_cert.public_key()
        issuer_public_key.verify(
            child_cert.signature,
            child_cert.tbs_certificate_bytes,
            crypto['ec'].ECDSA(child_cert.signature_hash_algorithm),
        )
        return True
    except Exception:
        try:
            from cryptography.hazmat.primitives.asymmetric import padding
            issuer_public_key.verify(
                child_cert.signature,
                child_cert.tbs_certificate_bytes,
                padding.PKCS1v15(),
                child_cert.signature_hash_algorithm,
            )
            return True
        except Exception as e:
            print(f'[AppStore] certificate chain verify failed: {e}')
            return False


def _is_trusted_app_store_chain(certs, crypto):
    if not certs:
        return False

    now = datetime.utcnow()
    for cert in certs:
        if cert.not_valid_before > now or cert.not_valid_after < now:
            print('[AppStore] certificate is not currently valid')
            return False

    for idx in range(len(certs) - 1):
        if not _verify_cert_signed_by(certs[idx], certs[idx + 1], crypto):
            return False

    if not APP_STORE_ROOT_CERT_PEM:
        return not APP_STORE_REQUIRE_TRUSTED_JWS

    try:
        trusted_root = crypto['x509'].load_pem_x509_certificate(
            APP_STORE_ROOT_CERT_PEM.replace('\\n', '\n').encode('utf-8')
        )
        if certs[-1].fingerprint(crypto['hashes'].SHA256()) == trusted_root.fingerprint(
            crypto['hashes'].SHA256()
        ):
            return True
        return _verify_cert_signed_by(certs[-1], trusted_root, crypto)
    except Exception as e:
        print(f'[AppStore] trusted root cert parse failed: {e}')
        return False


def _decode_signed_payload(jws, *, verify=True):
    if not jws or not isinstance(jws, str):
        return None
    parts = jws.split('.')
    if len(parts) != 3:
        print('[AppStore] invalid JWS compact form')
        return None

    try:
        header = json.loads(_b64url_decode(parts[0]).decode('utf-8'))
        payload = json.loads(_b64url_decode(parts[1]).decode('utf-8'))
    except Exception as e:
        print(f'[AppStore] JWS decode failed: {e}')
        return None

    if not verify:
        return payload

    crypto = _crypto_imports()
    if crypto is None:
        return None

    try:
        x5c = header.get('x5c') or []
        if not x5c:
            print('[AppStore] JWS missing x5c certificate chain')
            return None

        certs = [
            crypto['x509'].load_der_x509_certificate(base64.b64decode(raw_cert))
            for raw_cert in x5c
        ]
        if not _is_trusted_app_store_chain(certs, crypto):
            print('[AppStore] JWS certificate chain is not trusted')
            return None

        signature = _b64url_decode(parts[2])
        if len(signature) != 64:
            print('[AppStore] ES256 signature is not 64 bytes')
            return None
        r = int.from_bytes(signature[:32], 'big')
        s = int.from_bytes(signature[32:], 'big')
        der_signature = crypto['encode_dss_signature'](r, s)
        signing_input = f'{parts[0]}.{parts[1]}'.encode('utf-8')
        certs[0].public_key().verify(
            der_signature,
            signing_input,
            crypto['ec'].ECDSA(crypto['hashes'].SHA256()),
        )
        return payload
    except Exception as e:
        print(f'[AppStore] JWS verification failed: {e}')
        return None


def _app_store_api_base(environment):
    return APP_STORE_SANDBOX_API if environment == 'sandbox' else APP_STORE_PRODUCTION_API


def _app_store_api_get(path, *, environment='production', query=None):
    token = _make_app_store_server_jwt()
    if not token:
        return None
    query_string = ''
    if query:
        query_string = '?' + urllib.parse.urlencode(query, doseq=True)
    url = _app_store_api_base(environment) + path + query_string
    req = urllib.request.Request(
        url,
        headers={
            'Authorization': f'Bearer {token}',
            'Accept': 'application/json',
        },
        method='GET',
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception as e:
        print(f'[AppStore] API GET failed env={environment} path={path}: {e}')
        return None


def _product_id_to_vip_type(product_id):
    product_id = product_id or ''
    if 'year' in product_id:
        return 'yearly'
    if 'mon' in product_id:
        return 'monthly'
    return ''


def _safe_vip_log_profile(profile):
    if not isinstance(profile, dict):
        return profile
    return {
        'vip_type': profile.get('vip_type', ''),
        'vip_expire_ms': profile.get('vip_expire_ms', 0),
        'vip_environment': profile.get('vip_environment', 'unknown'),
        'vip_verify_status': profile.get('vip_verify_status', ''),
        'vip_verify_error': profile.get('vip_verify_error', ''),
        'product_id': profile.get('product_id', ''),
        'has_transaction_id': bool(profile.get('transaction_id')),
        'has_original_transaction_id': bool(profile.get('original_transaction_id')),
        'has_app_account_token': bool(profile.get('app_account_token')),
        'purchase_ms': profile.get('purchase_ms', 0),
        'revocation_ms': profile.get('revocation_ms', 0),
    }


def _extract_ms(value):
    if value is None:
        return 0
    try:
        return int(value)
    except Exception:
        return 0


def _vip_profile_from_transaction_payload(transaction, *, environment, source, notification_type=''):
    if not isinstance(transaction, dict):
        return None
    bundle_id = transaction.get('bundleId') or ''
    if bundle_id and bundle_id != APP_STORE_BUNDLE_ID:
        print(f'[AppStore] ignore transaction for bundle_id={bundle_id}')
        return None

    product_id = transaction.get('productId') or ''
    expires_ms = _extract_ms(transaction.get('expiresDate'))
    purchase_ms = _extract_ms(transaction.get('purchaseDate'))
    revoked_ms = _extract_ms(transaction.get('revocationDate'))
    transaction_id = str(transaction.get('transactionId') or '')
    original_transaction_id = str(transaction.get('originalTransactionId') or '')
    app_account_token = str(transaction.get('appAccountToken') or '')

    if revoked_ms > 0:
        expires_ms = min(expires_ms, revoked_ms) if expires_ms > 0 else revoked_ms

    profile = {
        'vip_type': _product_id_to_vip_type(product_id),
        'vip_expire_ms': expires_ms,
        'vip_environment': environment or 'unknown',
        'vip_verify_status': source,
        'vip_verify_error': notification_type,
        'product_id': product_id,
        'transaction_id': transaction_id,
        'original_transaction_id': original_transaction_id,
        'app_account_token': app_account_token,
        'purchase_ms': purchase_ms,
        'revocation_ms': revoked_ms,
        'updated_at': datetime.now().isoformat(),
    }
    return profile


def _fetch_latest_vip_profile_from_app_store(transaction_id, *, preferred_environment=None):
    if not transaction_id or not _is_app_store_server_api_configured():
        return None

    environments = []
    if preferred_environment in ('production', 'sandbox'):
        environments.append(preferred_environment)
    for env in (APP_STORE_SERVER_API_ENV, 'production', 'sandbox'):
        if env in ('production', 'sandbox') and env not in environments:
            environments.append(env)

    for env in environments:
        response = _app_store_api_get(
            f'/inApps/v1/subscriptions/{urllib.parse.quote(str(transaction_id), safe="")}',
            environment=env,
        )
        if not response:
            continue

        latest_profile = None
        for item in response.get('data') or []:
            for tx in item.get('lastTransactions') or []:
                signed_transaction = tx.get('signedTransactionInfo')
                transaction = _decode_signed_payload(signed_transaction)
                profile = _vip_profile_from_transaction_payload(
                    transaction,
                    environment=env,
                    source='app_store_server_api',
                )
                if profile and (
                    latest_profile is None
                    or int(profile.get('vip_expire_ms', 0) or 0) > int(latest_profile.get('vip_expire_ms', 0) or 0)
                ):
                    latest_profile = profile
        if latest_profile:
            return latest_profile
    return None


def _merge_vip_profile(existing_profile, incoming_profile):
    if not incoming_profile:
        return existing_profile or {}
    if not existing_profile:
        return incoming_profile

    existing_environment = existing_profile.get('vip_environment', 'unknown')
    incoming_environment = incoming_profile.get('vip_environment', 'unknown')
    existing_expire_ms = int(existing_profile.get('vip_expire_ms', 0) or 0)
    incoming_expire_ms = int(incoming_profile.get('vip_expire_ms', 0) or 0)
    incoming_verify_status = incoming_profile.get('vip_verify_status', '')
    incoming_is_apple_authoritative = (
        incoming_verify_status in ('app_store_server_api', 'app_store_notification', 0, '0')
    )

    if _vip_environment_priority(existing_environment) > _vip_environment_priority(incoming_environment):
        return existing_profile
    # Apple-verified subscription state must be authoritative, even when it is
    # shorter than a previously cached client-calculated expiry. This matters
    # especially in sandbox, where subscription durations are accelerated.
    if incoming_is_apple_authoritative and incoming_expire_ms > 0:
        return {**existing_profile, **incoming_profile}
    if incoming_expire_ms <= 0 and existing_expire_ms > 0:
        return {**existing_profile, **incoming_profile}
    if existing_expire_ms > incoming_expire_ms and incoming_profile.get('revocation_ms', 0) <= 0:
        return existing_profile
    return {**existing_profile, **incoming_profile}


def _verify_receipt_with_apple(receipt_data):
    if not receipt_data:
        return None
    if not APP_STORE_SHARED_SECRET:
        print('[VIP] APP_STORE_SHARED_SECRET not configured, skip Apple verify')
        return {
            'environment': 'unknown',
            'receipt_info': None,
            'verify_status': 'missing_secret',
            'verify_error': 'APP_STORE_SHARED_SECRET not configured',
        }

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
                'receipt_info': data.get('latest_receipt_info') or data.get('receipt'),
                'verify_status': status,
                'verify_error': '',
            }
        if status == 21007:
            data = _post(SANDBOX_VERIFY_URL)
            status = data.get('status', -1)
            print(f'[VIP] Apple verify sandbox status={status}')
            if status == 0:
                return {
                    'environment': 'sandbox',
                    'receipt_info': data.get('latest_receipt_info') or data.get('receipt'),
                    'verify_status': status,
                    'verify_error': '',
                }
        print(f'[VIP] Apple verify unresolved status={status}')
        return {
            'environment': 'unknown',
            'receipt_info': None,
            'verify_status': status,
            'verify_error': '',
        }
    except Exception as e:
        print(f'[VIP] Apple verify error: {e}')
        return {
            'environment': 'unknown',
            'receipt_info': None,
            'verify_status': 'exception',
            'verify_error': str(e),
        }


def _apple_subscription_expire_ms(receipt_info):
    receipt_info = _pick_latest_receipt_info(receipt_info)
    if not receipt_info:
        return 0

    expires_date_ms = receipt_info.get('expires_date_ms') or receipt_info.get('subscription-expire-date-ms')
    if expires_date_ms:
        try:
            return int(expires_date_ms)
        except Exception:
            pass
    return 0


def _pick_latest_receipt_info(receipt_info):
    if not receipt_info:
        return {}
    if isinstance(receipt_info, dict):
        return receipt_info
    if not isinstance(receipt_info, list):
        return {}

    best_item = {}
    best_expire_ms = -1
    best_purchase_ms = -1

    for item in receipt_info:
        if not isinstance(item, dict):
            continue
        expire_raw = item.get('expires_date_ms') or item.get('subscription-expire-date-ms') or 0
        purchase_raw = item.get('purchase_date_ms') or item.get('original_purchase_date_ms') or 0

        try:
            expire_ms = int(expire_raw)
        except Exception:
            expire_ms = 0

        try:
            purchase_ms = int(purchase_raw)
        except Exception:
            purchase_ms = 0

        if expire_ms > best_expire_ms or (expire_ms == best_expire_ms and purchase_ms > best_purchase_ms):
            best_item = item
            best_expire_ms = expire_ms
            best_purchase_ms = purchase_ms

    return best_item


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
                    'APP_STORE_SHARED_SECRET_LEN': len(APP_STORE_SHARED_SECRET),
                    'APP_STORE_BUNDLE_ID': APP_STORE_BUNDLE_ID,
                    'APP_STORE_SERVER_ISSUER_ID_LEN': len(APP_STORE_SERVER_ISSUER_ID),
                    'APP_STORE_SERVER_KEY_ID_LEN': len(APP_STORE_SERVER_KEY_ID),
                    'APP_STORE_SERVER_PRIVATE_KEY_CONFIGURED': bool(APP_STORE_SERVER_PRIVATE_KEY or APP_STORE_SERVER_PRIVATE_KEY_PATH),
                    'APP_STORE_ROOT_CERT_CONFIGURED': bool(APP_STORE_ROOT_CERT_PEM),
                    'APP_STORE_REQUIRE_TRUSTED_JWS': APP_STORE_REQUIRE_TRUSTED_JWS,
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

        elif self.path in ('/app-store/notifications', '/app-store/notifications/v2'):
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body) if body else {}

            signed_payload = data.get('signedPayload')
            notification = _decode_signed_payload(signed_payload)
            if not notification:
                self._respond(400, {'error': 'invalid_signed_payload'})
                return

            notification_type = notification.get('notificationType', '')
            subtype = notification.get('subtype', '')
            notification_data = notification.get('data') or {}
            bundle_id = notification_data.get('bundleId') or ''
            if bundle_id and bundle_id != APP_STORE_BUNDLE_ID:
                print(f'[AppStore] ignore notification for bundle_id={bundle_id}')
                self._respond(200, {'accepted': True, 'ignored': 'bundle_id_mismatch'})
                return

            environment = str(notification_data.get('environment') or notification.get('environment') or 'unknown').lower()
            if environment not in ('production', 'sandbox'):
                environment = 'unknown'

            signed_transaction = notification_data.get('signedTransactionInfo')
            transaction = _decode_signed_payload(signed_transaction)
            incoming_profile = _vip_profile_from_transaction_payload(
                transaction,
                environment=environment,
                source='app_store_notification',
                notification_type=':'.join([v for v in (notification_type, subtype) if v]),
            )
            if not incoming_profile:
                print(f'[AppStore] notification has no usable transaction, type={notification_type} subtype={subtype}')
                self._respond(200, {'accepted': True, 'mapped': False, 'reason': 'no_transaction'})
                return

            user_phone = _ots_find_vip_user_by_subscription(
                app_account_token=incoming_profile.get('app_account_token', ''),
                transaction_id=incoming_profile.get('transaction_id', ''),
                original_transaction_id=incoming_profile.get('original_transaction_id', ''),
            )
            if not user_phone:
                print(
                    '[AppStore] notification accepted but not mapped: '
                    f'type={notification_type} subtype={subtype} '
                    f'has_tx={bool(incoming_profile.get("transaction_id", ""))}'
                )
                self._respond(200, {'accepted': True, 'mapped': False})
                return

            existing_profile = _ots_get_vip_profile(user_phone)
            profile = _merge_vip_profile(existing_profile, incoming_profile)
            success = _ots_put_vip_profile(user_phone, profile)
            if success:
                print(f'[AppStore] notification saved user={user_phone} type={notification_type} subtype={subtype}')
                self._respond(200, {'accepted': True, 'mapped': True, 'profile': profile})
            else:
                self._respond(500, {'error': 'OTS vip write failed'})

        elif self.path == '/vip/refresh':
            user_phone = self._get_user_phone()
            if not user_phone:
                self._respond(400, {'error': 'Missing X-User-Phone header'})
                return

            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length).decode('utf-8')
            data = json.loads(body) if body else {}
            existing_profile = _ots_get_vip_profile(user_phone)
            transaction_id = str(
                data.get('transaction_id')
                or existing_profile.get('transaction_id')
                or existing_profile.get('original_transaction_id')
                or ''
            ).strip()
            preferred_environment = str(
                data.get('vip_environment')
                or existing_profile.get('vip_environment')
                or ''
            ).lower()

            if not transaction_id:
                self._respond(400, {'error': 'missing_transaction_id'})
                return

            incoming_profile = _fetch_latest_vip_profile_from_app_store(
                transaction_id,
                preferred_environment=preferred_environment,
            )
            if not incoming_profile:
                self._respond(502, {'error': 'app_store_lookup_failed'})
                return

            if existing_profile.get('app_account_token') and not incoming_profile.get('app_account_token'):
                incoming_profile['app_account_token'] = existing_profile.get('app_account_token')
            profile = _merge_vip_profile(existing_profile, incoming_profile)
            success = _ots_put_vip_profile(user_phone, profile)
            if success:
                self._respond(200, {'profile': profile})
            else:
                self._respond(500, {'error': 'OTS vip write failed'})

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
            transaction_id = str(data.get('transaction_id') or '').strip()
            original_transaction_id = str(data.get('original_transaction_id') or '').strip()
            app_account_token = str(data.get('app_account_token') or '').strip()
            incoming_environment = data.get('vip_environment', 'unknown') or 'unknown'
            existing_profile = _ots_get_vip_profile(user_phone)
            existing_environment = existing_profile.get('vip_environment', 'unknown')
            existing_expire_ms = int(existing_profile.get('vip_expire_ms', 0) or 0)
            product_id = ''
            purchase_ms = 0
            revocation_ms = 0

            print(
                f'[VIP] /vip/sync user={user_phone} vip_type={vip_type} expire_ms={vip_expire_ms} '
                f'incoming_env={incoming_environment} existing_env={existing_environment} '
                f'has_receipt={bool(receipt_data)} has_tx={bool(transaction_id)} '
                f'has_app_account_token={bool(app_account_token)}'
            )

            server_profile = _fetch_latest_vip_profile_from_app_store(
                transaction_id or existing_profile.get('transaction_id', ''),
                preferred_environment=incoming_environment.lower() if isinstance(incoming_environment, str) else None,
            )
            if server_profile:
                if app_account_token and not server_profile.get('app_account_token'):
                    server_profile['app_account_token'] = app_account_token
                profile = _merge_vip_profile(existing_profile, server_profile)
                success = _ots_put_vip_profile(user_phone, profile)
                if success:
                    print(f'[VIP] /vip/sync saved server profile={_safe_vip_log_profile(profile)}')
                    self._respond(200, {'profile': profile})
                else:
                    self._respond(500, {'error': 'OTS vip write failed'})
                return

            if receipt_data:
                receipt_result = _verify_receipt_with_apple(receipt_data)
                verify_status = ''
                verify_error = ''
                if receipt_result is not None:
                    incoming_environment = receipt_result.get('environment', 'unknown')
                    verify_status = receipt_result.get('verify_status', '')
                    verify_error = receipt_result.get('verify_error', '')
                    receipt_info = receipt_result.get('receipt_info')
                    latest_receipt_info = _pick_latest_receipt_info(receipt_info)
                    apple_expire_ms = _apple_subscription_expire_ms(latest_receipt_info)
                    if isinstance(latest_receipt_info, dict):
                        product_id = latest_receipt_info.get('product_id', '')
                        transaction_id = transaction_id or str(latest_receipt_info.get('transaction_id') or '')
                        original_transaction_id = (
                            original_transaction_id
                            or str(latest_receipt_info.get('original_transaction_id') or '')
                        )
                        purchase_ms = _extract_ms(
                            latest_receipt_info.get('purchase_date_ms')
                            or latest_receipt_info.get('original_purchase_date_ms')
                        )
                    if apple_expire_ms > 0:
                        vip_expire_ms = apple_expire_ms
                        if 'year' in product_id:
                            vip_type = 'yearly'
                        elif 'mon' in product_id:
                            vip_type = 'monthly'
                else:
                    print('[VIP] receipt verify returned None, keeping incoming environment')
                    verify_status = 'none'
                    verify_error = 'verify returned None'
            else:
                verify_status = 'no_receipt'
                verify_error = ''

            # 保护规则 1：sandbox / unknown 不允许覆盖更高优先级记录
            if existing_profile and _vip_environment_priority(existing_environment) > _vip_environment_priority(incoming_environment):
                print(f'[VIP] ignore lower-priority profile: incoming={incoming_environment} existing={existing_environment}')
                self._respond(200, {'profile': existing_profile})
                return

            # 保护规则 2：只要现有档案已存在，未经 Apple 验证出的 unknown 一律不允许覆盖。
            # 这样可以挡住 TestFlight/restore 本地错误日期在 receipt 未校验成功时再次把云端改坏。
            if existing_profile and incoming_environment == 'unknown' and existing_environment in ('unknown', 'production'):
                if receipt_data and vip_expire_ms >= existing_expire_ms:
                    print(
                        f'[VIP] allow unknown overwrite with receipt because expire_ms is not older: '
                        f'incoming={vip_expire_ms} existing={existing_expire_ms}'
                    )
                else:
                    print(f'[VIP] ignore unknown overwrite: incoming={incoming_environment} existing={existing_environment}')
                    self._respond(200, {'profile': existing_profile})
                    return

            if vip_expire_ms > 0 and _is_vip_expired(vip_expire_ms):
                self._respond(403, {
                    'error': 'subscription_expired',
                    'message': '会员已过期，拒绝写入过期状态'
                })
                return

            if not vip_type and vip_expire_ms <= 0:
                print('[VIP] /vip/sync no active subscription in receipt, skip empty profile write')
                self._respond(200, {'profile': existing_profile or {}})
                return

            profile = {
                'vip_type': vip_type,
                'vip_expire_ms': vip_expire_ms,
                'vip_environment': incoming_environment,
                'vip_verify_status': verify_status,
                'vip_verify_error': verify_error,
                'product_id': product_id,
                'transaction_id': transaction_id,
                'original_transaction_id': original_transaction_id,
                'app_account_token': app_account_token or existing_profile.get('app_account_token', ''),
                'purchase_ms': purchase_ms,
                'revocation_ms': revocation_ms,
                'updated_at': datetime.now().isoformat(),
            }

            success = _ots_put_vip_profile(user_phone, profile)
            if success:
                print(f'[VIP] /vip/sync saved profile={_safe_vip_log_profile(profile)}')
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
