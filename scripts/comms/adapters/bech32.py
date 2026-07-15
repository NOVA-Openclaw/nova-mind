#!/usr/bin/env python3
"""
Minimal bech32 / bech32m encoder/decoder for Nostr npub <-> hex conversion.

This is a self-contained implementation of BIP-173/350 so the Nostr adapter can
normalize pubkey formats without adding a dependency. It only supports the
"npub" hrp used by NIP-19 public keys.
"""

from __future__ import annotations

CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
BECH32_GENERATOR = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]


def _polymod(values: list[int]) -> int:
    chk = 1
    for v in values:
        b = chk >> 25
        chk = (chk & 0x1FFFFFF) << 5 ^ v
        for i in range(5):
            chk ^= BECH32_GENERATOR[i] if (b >> i) & 1 else 0
    return chk


def _hrp_expand(hrp: str) -> list[int]:
    return [ord(x) >> 5 for x in hrp] + [0] + [ord(x) & 31 for x in hrp]


def _verify_checksum(hrp: str, data: list[int]) -> str:
    polymod = _polymod(_hrp_expand(hrp) + data)
    if polymod == 1:
        return "bech32"
    if polymod == 0x2BC830A3:
        return "bech32m"
    return ""


def _create_checksum(hrp: str, data: list[int], spec: str = "bech32") -> list[int]:
    polymod = _polymod(_hrp_expand(hrp) + data + [0] * 6)
    if spec == "bech32m":
        polymod ^= 0x2BC830A3
    else:
        polymod ^= 1
    return [(polymod >> 5 * (5 - i)) & 31 for i in range(6)]


def _convert_bits(data: list[int], from_bits: int, to_bits: int, pad: bool = True) -> list[int]:
    acc = 0
    bits = 0
    ret: list[int] = []
    maxv = (1 << to_bits) - 1
    max_acc = (1 << (from_bits + to_bits - 1)) - 1
    for value in data:
        if value < 0 or (value >> from_bits):
            raise ValueError("invalid value in convert_bits")
        acc = ((acc << from_bits) | value) & max_acc
        bits += from_bits
        while bits >= to_bits:
            bits -= to_bits
            ret.append((acc >> bits) & maxv)
    if pad:
        if bits:
            ret.append((acc << (to_bits - bits)) & maxv)
    elif bits >= from_bits or ((acc << (to_bits - bits)) & maxv):
        raise ValueError("invalid padding")
    return ret


def decode(bech: str) -> tuple[str, list[int], str]:
    """Decode a bech32/bech32m string into (hrp, data_bytes, spec)."""
    if (any(ord(x) < 33 or ord(x) > 126 for x in bech)) or (bech.lower() != bech and bech.upper() != bech):
        raise ValueError("invalid bech32 string")
    bech = bech.lower()
    pos = bech.rfind("1")
    if pos < 1 or pos + 7 > len(bech) or pos > 83:
        raise ValueError("invalid bech32 human-readable part")
    if any(CHARSET.find(x) == -1 for x in bech[pos + 1 :]):
        raise ValueError("invalid bech32 data characters")
    hrp = bech[:pos]
    data = [CHARSET.find(x) for x in bech[pos + 1 :]]
    spec = _verify_checksum(hrp, data)
    if not spec:
        raise ValueError("invalid bech32 checksum")
    return hrp, _convert_bits(data[:-6], 5, 8, False), spec


def encode(hrp: str, data: bytes, spec: str = "bech32") -> str:
    """Encode bytes as a bech32/bech32m string."""
    values = _convert_bits(list(data), 8, 5, True)
    checksum = _create_checksum(hrp, values, spec)
    return hrp + "1" + "".join(CHARSET[v] for v in values + checksum)


def npub_to_hex(npub: str) -> str:
    """Convert an npub bech32 string to a lowercase hex pubkey."""
    hrp, data, _ = decode(npub)
    if hrp != "npub":
        raise ValueError(f"expected npub hrp, got {hrp}")
    return bytes(data).hex()


def hex_to_npub(hex_key: str) -> str:
    """Convert a 32-byte hex pubkey to an npub bech32 string."""
    raw = bytes.fromhex(hex_key)
    if len(raw) != 32:
        raise ValueError(f"expected 32-byte pubkey, got {len(raw)} bytes")
    return encode("npub", raw)
