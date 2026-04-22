#!/usr/bin/env python3
import sys, os, json, uuid, time, hmac, hashlib, base64, urllib.parse, random, string
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
print('[FC] Imports OK', flush=True)

SMS_CODES_FILE = '/tmp/sms_codes.json'
DELETED_USERS_FILE = '/tmp/deleted_users.json'
SOFT_DELETE_DAYS = 30  # 注销后30天内可恢复
ALIYUN_ACCESS_KEY_ID = os.environ.get('ALIYUN_ACCESS_KEY_ID', '')
ALIYUN_ACCESS_KEY_SECRET = os.environ.get('ALIYUN_ACCESS_KEY_SECRET', '')
ALIYUN_SMS_SIGN_NAME = os.environ.get('ALIYUN_SMS_SIGN_NAME', 'AI财富账本')
ALIYUN_SMS_TEMPLATE_CODE = os.environ.get('ALIYUN_SMS_TEMPLATE_CODE', '')
SMS_REGION = 'cn-hangzhou'

APP_STORE_SHARED_SECRET = os.environ.get('APP_STORE_SHARED_SECRET', '')
APPLE_VERIFY_URL = 'https://buy.itunes.apple.com/verifyReceipt'
SANDBOX_VERIFY_URL = 'https://sandbox.itunes.apple.com/verifyReceipt'


def _phone_file(phone, suffix=''):
    safe = urllib.parse.quote(str(phone), safe='')
    return f'/tmp/entries_{safe}{suffix}.json'


def _asset_phone_file(phone):
    safe = urllib.parse.quote(str(phone), safe='')
    return f'/tmp/assets_{safe}.json'


def _stock_phone_file(phone):
    safe = urllib.parse.quote(str(phone), safe='')
    return f'/tmp/stock_positions_{safe}.json'


def _vip_phone_file(phone):
    safe = urllib.parse.quote(str(phone), safe='')
    return f'/tmp/vip_{safe}.json'


def _load_json(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except:
        return {}


def _save_json(path, data):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _load(phone):
    if not phone:
        return []
    data = _load_json(_phone_file(phone))
    return data if isinstance(data, list) else []


def _save(phone, entries):
    if not phone:
        return
    _save_json(_phone_file(phone), entries)


def _load_assets(phone):
    if not phone:
        return []
    data = _load_json(_asset_phone_file(phone))
    return data if isinstance(data, list) else []


def _save_assets(phone, assets):
    if not phone:
        return
    _save_json(_asset_phone_file(phone), assets)


def _load_stock_positions(phone):
    if not phone:
        return []
    data = _load_json(_stock_phone_file(phone))
    return data if isinstance(data, list) else []


def _save_stock_positions(phone, positions):
    if not phone:
        return
    _save_json(_stock_phone_file(phone), positions)


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


def _normalize_asset(body, now=None, asset_id=None):
    now = now or datetime.now().isoformat()
    return {
        'id': asset_id or body.get('id') or str(uuid.uuid4()),
        'name': body.get('name', ''),
        'type': body.get('type', 'cash'),
        'balance': float(body.get('balance', 0) or 0),
        'currency': body.get('currency', 'CNY'),
        'locale': body.get('locale', 'zh-CN'),
        'countryCode': body.get('countryCode', 'CN'),
        'description': body.get('description'),
        'createdAt': body.get('createdAt', now),
        'syncStatus': body.get('syncStatus', 'synced'),
    }


def _normalize_stock_position(body, now=None, position_id=None):
    now = now or datetime.now().isoformat()
    exchange = body.get('exchange', '')
    return {
        'id': position_id or body.get('id') or str(uuid.uuid4()),
        'assetType': body.get('assetType', 'stock'),
        'code': body.get('code', ''),
        'name': body.get('name', ''),
        'exchange': exchange,
        'marketCurrency': body.get('marketCurrency', _default_currency_for_exchange(exchange)),
        'locale': body.get('locale', _default_locale_for_exchange(exchange)),
        'countryCode': body.get('countryCode', _default_country_for_exchange(exchange)),
        'quantity': int(body.get('quantity', 0) or 0),
        'costPrice': body.get('costPrice'),
        'latestPrice': body.get('latestPrice'),
        'changePercent': body.get('changePercent'),
        'quoteUpdatedAt': body.get('quoteUpdatedAt'),
        'quoteStatus': body.get('quoteStatus', 'loading'),
        'createdAt': body.get('createdAt', now),
        'updatedAt': body.get('updatedAt', now),
    }


def _load_sms():
    return _load_json(SMS_CODES_FILE)


def _save_sms(c):
    _save_json(SMS_CODES_FILE, c)


def _load_deleted_users():
    """加载注销用户表 {phone: deleted_at_iso}"""
    try:
        with open(DELETED_USERS_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except:
        return {}


def _save_deleted_users(data):
    """保存注销用户表"""
    _save_json(DELETED_USERS_FILE, data)


def _is_user_soft_deleted(phone):
    """检查用户是否已软注销（30天内可恢复）"""
    if not phone:
        return False
    deleted = _load_deleted_users()
    if phone in deleted:
        deleted_at = datetime.fromisoformat(deleted[phone])
        days_since = (datetime.now() - deleted_at).days
        if days_since < SOFT_DELETE_DAYS:
            return True
        else:
            del deleted[phone]
            _save_deleted_users(deleted)
    return False


def _soft_delete_user(phone):
    """软注销用户（不清除数据文件，30天内可恢复）"""
    deleted = _load_deleted_users()
    deleted[phone] = datetime.now().isoformat()
    _save_deleted_users(deleted)
    print(f'[FC] User soft-deleted: {phone}', flush=True)


def _restore_user(phone):
    """恢复已注销用户"""
    deleted = _load_deleted_users()
    if phone in deleted:
        del deleted[phone]
        _save_deleted_users(deleted)
        print(f'[FC] User restored: {phone}', flush=True)


# ── VIP 档案 ────────────────────────────────────────


def _load_vip_profile(phone):
    """加载 VIP 配置 {vip_type, vip_expire_ms, updated_at}"""
    if not phone:
        return {}
    path = _vip_phone_file(phone)
    if not os.path.exists(path):
        return {}
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except:
        return {}


def _save_vip_profile(phone, profile):
    """保存 VIP 配置"""
    if not phone:
        return
    path = _vip_phone_file(phone)
    _save_json(path, profile)


def _is_vip_expired(expire_ms):
    """判断 VIP 是否已过期（expire_ms 为毫秒时间戳）"""
    if not expire_ms or expire_ms <= 0:
        return True
    return datetime.now().timestamp() * 1000 > expire_ms


def _verify_receipt_with_apple(receipt_data):
    """向 Apple 验证 receipt，返回 {environment, receipt_info} 或 None"""
    if not receipt_data:
        return None
    if not APP_STORE_SHARED_SECRET:
        print('[FC] APP_STORE_SHARED_SECRET not configured, skipping Apple verify', flush=True)
        return None

    print(f'[FC] Apple verify start, receipt_len={len(receipt_data)}', flush=True)

    payload = json.dumps({
        'receipt-data': receipt_data,
        'password': APP_STORE_SHARED_SECRET,
        'exclude-old-transactions': True,
    })

    def _post(url):
        import urllib.request
        req = urllib.request.Request(
            url,
            data=payload.encode(),
            headers={'Content-Type': 'application/json'},
            method='POST',
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode())

    try:
        data = _post(APPLE_VERIFY_URL)
        status = data.get('status', -1)
        print(f'[FC] Apple verify production status={status}', flush=True)
        if status == 0:
            return {
                'environment': 'production',
                'receipt_info': data.get('latest_receipt_info') or data.get('receipt'),
            }
        if status == 21007:
            data = _post(SANDBOX_VERIFY_URL)
            status = data.get('status', -1)
            print(f'[FC] Apple verify sandbox status={status}', flush=True)
            if status == 0:
                return {
                    'environment': 'sandbox',
                    'receipt_info': data.get('latest_receipt_info') or data.get('receipt'),
                }
        print(f'[FC] Apple verify unresolved status={status}', flush=True)
    except Exception as e:
        print(f'[FC] Apple verify error: {e}', flush=True)
    return None


def _apple_subscription_expire_ms(receipt_info):
    """从 Apple receipt_info 中提取订阅到期时间（毫秒时间戳），返回 0 表示永久无效"""
    if not receipt_info:
        return 0
    if isinstance(receipt_info, list):
        receipt_info = receipt_info[-1] if receipt_info else {}
    expires_date_ms = receipt_info.get('expires_date_ms') or receipt_info.get('expires_date')
    if expires_date_ms:
        try:
            val = int(expires_date_ms)
            if val > 0:
                return val
        except:
            pass
    sub_exp = receipt_info.get('subscription-expire-date-ms')
    if sub_exp:
        try:
            val = int(sub_exp)
            if val > 0:
                return val
        except:
            pass
    return 0


# ── 阿里云签名 & 短信 ───────────────────────────────


def _aliyun_sig(method, path, queries):
    sq = sorted(queries.items())
    qs = '&'.join(f'{k}={urllib.parse.quote(str(v), safe="~")}' for k, v in sq)
    sts = f'{method}&%2F&{urllib.parse.quote(qs, safe="")}'
    key = f'{ALIYUN_ACCESS_KEY_SECRET}&'
    return base64.b64encode(hmac.new(key.encode(), sts.encode(), hashlib.sha1).digest()).decode()


def _send_sms(phone, code):
    if not ALIYUN_ACCESS_KEY_ID or not ALIYUN_SMS_TEMPLATE_CODE:
        return {'code': 'ConfigMissing'}
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
    params['Signature'] = _aliyun_sig('GET', '/', params)
    url = 'https://dysmsapi.aliyuncs.com/?' + urllib.parse.urlencode(params)
    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            return json.loads(r.read().decode())
    except Exception as e:
        return {'code': 'NetworkError', 'message': str(e)}


def _gen_code():
    return ''.join(random.choices(string.digits, k=6))


# ── 请求入口 ────────────────────────────────────────


def handler(event, context):
    method = event.get('method', 'GET').upper()
    path = event.get('path', '/')
    hdrs = event.get('headers', {})
    body_str = event.get('body', '')

    if method == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type,X-User-Phone,accept',
            },
            'body': '',
        }

    phone = hdrs.get('x-user-phone', '')
    if not phone:
        return {'statusCode': 400, 'headers': {}, 'body': json.dumps({'error': 'Missing X-User-Phone'})}

    body = {}
    if body_str:
        try:
            body = json.loads(body_str) if isinstance(body_str, str) else body_str
        except:
            pass

    try:
        # ── GET /entries ────────────────────────────────
        if method == 'GET' and (path == '/entries' or path.startswith('/entries?')):
            entries = _load(phone)
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'entries': entries, 'total': len(entries)}),
            }

        # ── POST /entries ──────────────────────────────
        if method == 'POST' and path == '/entries':
            now = datetime.now().isoformat()
            eid = body.get('id') or str(uuid.uuid4())
            e = {
                'id': eid,
                'amount': float(body.get('amount', 0)),
                'type': body.get('type', 'expense'),
                'category': body.get('category', 'other'),
                'description': body.get('description', ''),
                'date': body.get('date', now),
                'createdAt': body.get('createdAt', now),
                'syncStatus': 'synced',
            }
            entries = _load(phone)
            idx = next((i for i, x in enumerate(entries) if x.get('id') == eid), None)
            if idx is not None:
                entries[idx] = e
            else:
                entries.append(e)
            _save(phone, entries)
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'entry': e}),
            }

        # ── PUT /entries/<id> ──────────────────────────
        if method == 'PUT' and path.startswith('/entries/'):
            eid = path.split('/')[-1]
            entries = _load(phone)
            idx = next((i for i, x in enumerate(entries) if x.get('id') == eid), None)
            if idx is None:
                return {'statusCode': 404, 'headers': {}, 'body': json.dumps({'error': 'Not found'})}
            for k in ['amount', 'type', 'category', 'description', 'date']:
                if k in body:
                    entries[idx][k] = body[k]
            entries[idx]['syncStatus'] = 'synced'
            _save(phone, entries)
            return {'statusCode': 200, 'headers': {}, 'body': json.dumps({'entry': entries[idx]})}

        # ── DELETE /entries/<id> ──────────────────────
        if method == 'DELETE' and path.startswith('/entries/'):
            eid = path.split('/')[-1]
            entries = _load(phone)
            idx = next((i for i, x in enumerate(entries) if x.get('id') == eid), None)
            if idx is not None:
                entries.pop(idx)
                _save(phone, entries)
            return {'statusCode': 200, 'headers': {}, 'body': json.dumps({'deleted': True})}

        # ── GET /assets ────────────────────────────────
        if method == 'GET' and (path == '/assets' or path.startswith('/assets?')):
            assets = _load_assets(phone)
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'assets': assets}),
            }

        # ── POST /assets ───────────────────────────────
        if method == 'POST' and path == '/assets':
            now = datetime.now().isoformat()
            a = _normalize_asset(body, now=now)
            assets = _load_assets(phone)
            assets.append(a)
            _save_assets(phone, assets)
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'asset': a}),
            }

        # ── PUT /assets/<id> ──────────────────────────
        if method == 'PUT' and path.startswith('/assets/'):
            aid = path.split('/')[-1]
            assets = _load_assets(phone)
            idx = next((i for i, x in enumerate(assets) if x.get('id') == aid), None)
            if idx is None:
                return {'statusCode': 404, 'headers': {}, 'body': json.dumps({'error': 'Not found'})}
            for k in ['name', 'type', 'balance', 'currency', 'locale', 'countryCode', 'description', 'createdAt']:
                if k in body:
                    assets[idx][k] = body[k]
            assets[idx]['syncStatus'] = body.get('syncStatus', 'synced')
            _save_assets(phone, assets)
            return {'statusCode': 200, 'headers': {}, 'body': json.dumps({'asset': assets[idx]})}

        # ── DELETE /assets/<id> ────────────────────────
        if method == 'DELETE' and path.startswith('/assets/'):
            aid = path.split('/')[-1]
            assets = _load_assets(phone)
            idx = next((i for i, x in enumerate(assets) if x.get('id') == aid), None)
            if idx is not None:
                assets.pop(idx)
                _save_assets(phone, assets)
            return {'statusCode': 200, 'headers': {}, 'body': json.dumps({'deleted': True})}

        # ── GET /stock_positions ──────────────────────
        if method == 'GET' and (path == '/stock_positions' or path.startswith('/stock_positions?')):
            positions = _load_stock_positions(phone)
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'stock_positions': positions}),
            }

        # ── POST /stock_positions ─────────────────────
        if method == 'POST' and path == '/stock_positions':
            now = datetime.now().isoformat()
            sid = body.get('id') or str(uuid.uuid4())
            p = _normalize_stock_position(body, now=now, position_id=sid)
            positions = _load_stock_positions(phone)
            idx = next((i for i, x in enumerate(positions) if x.get('id') == sid or x.get('code') == p['code']), None)
            if idx is not None:
                positions[idx] = p
            else:
                positions.append(p)
            _save_stock_positions(phone, positions)
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'stock_position': p}),
            }

        # ── PUT /stock_positions ───────────────────────
        if method == 'PUT' and path == '/stock_positions':
            positions = body.get('stock_positions', [])
            if not isinstance(positions, list):
                return {'statusCode': 400, 'headers': {}, 'body': json.dumps({'error': 'stock_positions must be a list'})}
            normalized = []
            for item in positions:
                if not isinstance(item, dict):
                    continue
                normalized.append(_normalize_stock_position(item))
            _save_stock_positions(phone, normalized)
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'stock_positions': normalized}),
            }

        # ── PUT /stock_positions/<id> ──────────────────
        if method == 'PUT' and path.startswith('/stock_positions/'):
            sid = path.split('/')[-1]
            positions = _load_stock_positions(phone)
            idx = next((i for i, x in enumerate(positions) if x.get('id') == sid), None)
            if idx is None:
                return {'statusCode': 404, 'headers': {}, 'body': json.dumps({'error': 'Not found'})}
            for k in ['assetType', 'code', 'name', 'exchange', 'marketCurrency', 'locale', 'countryCode', 'quantity', 'costPrice', 'latestPrice', 'changePercent', 'quoteUpdatedAt', 'quoteStatus', 'createdAt', 'updatedAt']:
                if k in body:
                    positions[idx][k] = body[k]
            _save_stock_positions(phone, positions)
            return {'statusCode': 200, 'headers': {}, 'body': json.dumps({'stock_position': positions[idx]})}

        # ── DELETE /stock_positions/<id> ───────────────
        if method == 'DELETE' and path.startswith('/stock_positions/'):
            sid = path.split('/')[-1]
            positions = _load_stock_positions(phone)
            idx = next((i for i, x in enumerate(positions) if x.get('id') == sid), None)
            if idx is not None:
                positions.pop(idx)
                _save_stock_positions(phone, positions)
            return {'statusCode': 200, 'headers': {}, 'body': json.dumps({'deleted': True})}

        # ── POST /sms/send ─────────────────────────────
        if method == 'POST' and path == '/sms/send':
            ph = body.get('phone', '').strip()
            if not ph or len(ph) < 11:
                return {'statusCode': 400, 'headers': {}, 'body': json.dumps({'error': 'Invalid phone'})}
            code = _gen_code()
            codes = _load_sms()
            codes[ph] = {'code': code, 'expire': int(time.time()) + 300}
            _save_sms(codes)
            r = _send_sms(ph, code) if ALIYUN_SMS_TEMPLATE_CODE else {'code': 'Mock'}
            return {
                'statusCode': 200,
                'headers': {},
                'body': json.dumps({'message': 'sent', 'simulated': r.get('code') in ('Mock', 'ConfigMissing')}),
            }

        # ── POST /sms/verify ──────────────────────────
        if method == 'POST' and path == '/sms/verify':
            ph = body.get('phone', '').strip()
            code = body.get('code', '').strip()
            codes = _load_sms()
            rec = codes.get(ph)
            if not rec:
                return {'statusCode': 200, 'headers': {}, 'body': json.dumps({'valid': False, 'reason': 'No code'})}
            if int(time.time()) > rec['expire']:
                return {'statusCode': 200, 'headers': {}, 'body': json.dumps({'valid': False, 'reason': 'Expired'})}
            if rec['code'] != code:
                return {'statusCode': 200, 'headers': {}, 'body': json.dumps({'valid': False, 'reason': 'Wrong code'})}
            del codes[ph]
            _save_sms(codes)
            restored = False
            if _is_user_soft_deleted(ph):
                _restore_user(ph)
                restored = True
            return {'statusCode': 200, 'headers': {}, 'body': json.dumps({'valid': True, 'restored': restored})}

        # ── DELETE /account ────────────────────────────
        if method == 'DELETE' and path == '/account':
            _soft_delete_user(phone)
            return {
                'statusCode': 200,
                'headers': {},
                'body': json.dumps({'deleted': True, 'recoverable_days': SOFT_DELETE_DAYS}),
            }

        # ── GET /vip ──────────────────────────────────
        if method == 'GET' and (path == '/vip' or path.startswith('/vip?')):
            profile = _load_vip_profile(phone)
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'profile': profile}),
            }

        # ── POST /vip/sync ─────────────────────────────
        if method == 'POST' and path == '/vip/sync':
            vip_type = body.get('vip_type', '')
            vip_expire_ms = body.get('vip_expire_ms', 0)
            receipt_data = body.get('receipt_data')
            incoming_environment = body.get('vip_environment', 'unknown') or 'unknown'

            print(
                f'[FC] /vip/sync phone={phone} vip_type={vip_type} expire_ms={vip_expire_ms} '
                f'incoming_env={incoming_environment} has_receipt={bool(receipt_data)}',
                flush=True,
            )

            if receipt_data:
                receipt_result = _verify_receipt_with_apple(receipt_data)
                if receipt_result is not None:
                    incoming_environment = receipt_result.get('environment', 'unknown')
                    receipt_info = receipt_result.get('receipt_info')
                    apple_expire_ms = _apple_subscription_expire_ms(receipt_info)
                    print(f'[FC] Apple verified expire_ms={apple_expire_ms}', flush=True)
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
                    print('[FC] Apple verify returned None, keeping incoming environment', flush=True)

            if vip_expire_ms > 0 and _is_vip_expired(vip_expire_ms):
                print(f'[FC] /vip/sync REJECTED: subscription expired (expire_ms={vip_expire_ms})', flush=True)
                return {
                    'statusCode': 403,
                    'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                    'body': json.dumps({
                        'error': 'subscription_expired',
                        'message': '会员已过期，云端拒绝写入过期状态',
                    }),
                }

            profile = {
                'vip_type': vip_type,
                'vip_expire_ms': vip_expire_ms,
                'vip_environment': incoming_environment,
                'updated_at': datetime.now().isoformat(),
            }
            _save_vip_profile(phone, profile)
            print(f'[FC] /vip/sync SAVED for {phone}: {profile}', flush=True)
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'profile': profile}),
            }

        return {'statusCode': 404, 'headers': {}, 'body': json.dumps({'error': 'Not found'})}

    except Exception as e:
        return {'statusCode': 500, 'headers': {}, 'body': json.dumps({'error': str(e)})}
