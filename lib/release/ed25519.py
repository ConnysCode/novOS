"""Ed25519 (RFC 8032) in plain Python, without any library beyond hashlib.

Used to sign releases in CI and to check them on the Mac and on the TV, whose Python has
no crypto library to rely on. Signing is not constant-time; it only ever runs on a CI
runner. Checked against the test vectors of RFC 8032, section 7.1, in test_release.py.
"""

import hashlib

_P = 2 ** 255 - 19
_L = 2 ** 252 + 27742317777372353535851937790883648493
_D = -121665 * pow(121666, _P - 2, _P) % _P
_SQRT_M1 = pow(2, (_P - 1) // 4, _P)


def _sha512(data):
    return hashlib.sha512(data).digest()


def _inverse(x):
    return pow(x, _P - 2, _P)


# Points in extended coordinates (X, Y, Z, T) with x = X/Z, y = Y/Z, x*y = T/Z.
def _add(p, q):
    a = (p[1] - p[0]) * (q[1] - q[0]) % _P
    b = (p[1] + p[0]) * (q[1] + q[0]) % _P
    c = p[3] * 2 * _D * q[3] % _P
    d = p[2] * 2 * q[2] % _P
    e, f, g, h = b - a, d - c, d + c, b + a
    return (e * f % _P, g * h % _P, f * g % _P, e * h % _P)


def _multiply(scalar, point):
    result = (0, 1, 1, 0)
    while scalar > 0:
        if scalar & 1:
            result = _add(result, point)
        point = _add(point, point)
        scalar >>= 1
    return result


def _equal(p, q):
    return (p[0] * q[2] - q[0] * p[2]) % _P == 0 and (p[1] * q[2] - q[1] * p[2]) % _P == 0


def _recover_x(y, sign):
    if y >= _P:
        return None
    x2 = (y * y - 1) * _inverse(_D * y * y + 1) % _P
    if x2 == 0:
        return None if sign else 0
    x = pow(x2, (_P + 3) // 8, _P)
    if (x * x - x2) % _P != 0:
        x = x * _SQRT_M1 % _P
    if (x * x - x2) % _P != 0:
        return None
    if (x & 1) != sign:
        x = _P - x
    return x


_GY = 4 * _inverse(5) % _P
_GX = _recover_x(_GY, 0)
_BASE = (_GX, _GY, 1, _GX * _GY % _P)


def _compress(point):
    zinv = _inverse(point[2])
    x = point[0] * zinv % _P
    y = point[1] * zinv % _P
    return (y | ((x & 1) << 255)).to_bytes(32, "little")


def _decompress(data):
    if len(data) != 32:
        return None
    y = int.from_bytes(data, "little")
    sign = y >> 255
    y &= (1 << 255) - 1
    x = _recover_x(y, sign)
    if x is None:
        return None
    return (x, y, 1, x * y % _P)


def _expand(secret):
    if len(secret) != 32:
        raise ValueError("an Ed25519 secret key has 32 bytes")
    digest = _sha512(secret)
    scalar = int.from_bytes(digest[:32], "little")
    scalar &= (1 << 254) - 8
    scalar |= 1 << 254
    return scalar, digest[32:]


def public_key(secret):
    """The 32-byte public key of a 32-byte secret key (seed)."""
    scalar, _ = _expand(secret)
    return _compress(_multiply(scalar, _BASE))


def sign(secret, message):
    """A 64-byte signature of message."""
    scalar, prefix = _expand(secret)
    public = _compress(_multiply(scalar, _BASE))
    r = int.from_bytes(_sha512(prefix + message), "little") % _L
    point_r = _compress(_multiply(r, _BASE))
    h = int.from_bytes(_sha512(point_r + public + message), "little") % _L
    s = (r + h * scalar) % _L
    return point_r + s.to_bytes(32, "little")


def verify(public, message, signature):
    """True if signature is a valid signature of message by public."""
    if len(public) != 32 or len(signature) != 64:
        return False
    point_a = _decompress(public)
    point_r = _decompress(signature[:32])
    if point_a is None or point_r is None:
        return False
    s = int.from_bytes(signature[32:], "little")
    if s >= _L:
        return False
    h = int.from_bytes(_sha512(signature[:32] + public + message), "little") % _L
    return _equal(_multiply(s, _BASE), _add(point_r, _multiply(h, point_a)))
