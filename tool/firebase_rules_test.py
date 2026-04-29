#!/usr/bin/env python3
"""Exercise actual Firebase rules with synthetic accounts in local emulators.

Run through check_firebase_rules.sh. No production config, account, or secret
is read. The fixed demo namespace and strict loopback checks are intentional.
"""

import json
import os
import time
import unittest
from urllib.error import HTTPError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen


def local_address(variable):
    address = os.environ.get(variable, "")
    parsed = urlsplit("http://" + address)
    if parsed.hostname not in ("127.0.0.1", "localhost", "::1") or not parsed.port:
        raise RuntimeError(f"{variable} must name a local emulator")
    return address


DATABASE = local_address("FIREBASE_DATABASE_EMULATOR_HOST")
AUTH = local_address("FIREBASE_AUTH_EMULATOR_HOST")
NAMESPACE = "demo-tripping-rules-default-rtdb"
NOW = {".sv": "timestamp"}
_MISSING = object()


def call(method, url, value=_MISSING, *, owner=False):
    data = None if value is _MISSING else json.dumps(value).encode()
    headers = {"Content-Type": "application/json"}
    if owner:
        headers["Authorization"] = "Bearer owner"  # Local-emulator admin only.
    try:
        with urlopen(Request(url, data, headers, method=method), timeout=10) as reply:
            return reply.status, json.load(reply)
    except HTTPError as error:
        status = error.code
        error.close()
        return status, None


def database(method, path, token=None, value=_MISSING, *, owner=False):
    query = {"ns": NAMESPACE}
    if token:
        query["auth"] = token
    return call(
        method,
        f"http://{DATABASE}/{path}.json?{urlencode(query)}",
        value,
        owner=owner,
    )


def account():
    status, value = call(
        "POST",
        f"http://{AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=synthetic",
        {"returnSecureToken": True},
    )
    if status != 200:
        raise RuntimeError("Local authentication emulator did not create an account")
    return value["localId"], value["idToken"]


class RoomRules(unittest.TestCase):
    def setUp(self):
        self.assertEqual(database("PUT", "", value=None, owner=True)[0], 200)
        self.a, self.at = account()
        self.b, self.bt = account()
        self.c, self.ct = account()
        self.room = "A" * 22  # Synthetic room capability; never a live room.
        self.path = f"rooms/{self.room}"
        self.assertAllowed(
            "PUT", "meta", self.at, {"created": NOW, "by": self.a}
        )
        self.join(self.a, self.at)

    def assertAllowed(self, method, path, token=None, value=_MISSING):
        status, result = database(method, f"{self.path}/{path}", token, value)
        self.assertEqual(status, 200, f"{method} {path} should be permitted")
        return result

    def assertDenied(self, method, path, token=None, value=_MISSING):
        status, _ = database(method, f"{self.path}/{path}", token, value)
        self.assertIn(status, (401, 403), f"{method} {path} should be refused")

    def join(self, uid, token):
        self.assertAllowed("PUT", f"members/{uid}", token, {"joined": NOW})

    def position(self, **overrides):
        return {"seq": 1, "at": NOW, "box": "e" * 100, **overrides}

    def seed(self, path, value):
        self.assertEqual(
            database("PUT", f"{self.path}/{path}", value=value, owner=True)[0], 200
        )

    def test_no_unauthenticated_access_or_room_listing(self):
        self.assertDenied("GET", "presence")
        self.assertDenied("PUT", f"members/{self.b}", value={"joined": NOW})
        for path in ("", "rooms", "s1", "s1/anything", "unrelated"):
            for method, value in (("GET", _MISSING), ("PUT", {"x": 1})):
                with self.subTest(path=path, method=method):
                    self.assertIn(database(method, path, self.at, value)[0], (401, 403))

    def test_existing_room_capability_allows_only_own_membership(self):
        self.assertDenied("GET", "presence", self.bt)
        self.assertDenied("PUT", f"members/{self.c}", self.bt, {"joined": NOW})
        self.join(self.b, self.bt)
        self.assertAllowed("GET", "presence", self.bt)
        self.assertAllowed("GET", "members", self.bt)
        self.assertAllowed("GET", "meta", self.bt)

    def test_nonexistent_and_malformed_room_cannot_be_joined(self):
        for room in ("B" * 22, "short"):
            self.assertIn(
                database("PUT", f"rooms/{room}/members/{self.b}", self.bt, {"joined": NOW})[0],
                (401, 403),
            )
        self.assertIn(
            database("PUT", "rooms/short/meta", self.bt, {"created": NOW, "by": self.b})[0],
            (401, 403),
        )

    def test_creator_and_creation_time_cannot_be_forged(self):
        for value in (
            {"created": NOW, "by": self.a},
            {"created": 1, "by": self.b},
            {"created": NOW, "by": self.b, "extra": True},
            {"created": NOW, "by": self.b, "closed": NOW},
        ):
            with self.subTest(fields=sorted(value)):
                self.assertIn(
                    database("PUT", f"rooms/{'B' * 22}/meta", self.bt, value)[0],
                    (401, 403),
                )

    def test_existing_room_cannot_be_replaced_or_closed_by_creator(self):
        self.assertDenied("PUT", "meta", self.bt, {"created": NOW, "by": self.b})
        self.assertDenied("PUT", "meta/closed", self.at, NOW)
        self.assertDenied("DELETE", "meta", self.at)

    def test_membership_timestamp_and_shape_are_checked(self):
        for value in ({"joined": 1}, {"joined": NOW, "extra": 1}, {"x": NOW}):
            with self.subTest(fields=sorted(value)):
                self.assertDenied("PUT", f"members/{self.b}", self.bt, value)

    def test_only_members_publish_in_own_slot(self):
        self.assertDenied("PUT", f"presence/{self.b}", self.bt, self.position())
        self.join(self.b, self.bt)
        self.assertDenied("PUT", f"presence/{self.a}", self.bt, self.position())
        self.assertAllowed("PUT", f"presence/{self.b}", self.bt, self.position())
        self.assertAllowed("GET", "presence", self.at)

    def test_rate_limit_is_enforced_by_server(self):
        self.assertAllowed("PUT", f"presence/{self.a}", self.at, self.position())
        self.assertDenied("PUT", f"presence/{self.a}", self.at, self.position(seq=2))
        time.sleep(2.1)
        self.assertAllowed("PUT", f"presence/{self.a}", self.at, self.position(seq=2))

    def test_sequence_is_a_positive_safe_integer(self):
        for seq in (0, -1, 1.5, "1", 9007199254740992):
            with self.subTest(seq=seq):
                # Isolate validation from the rate limiter even if a
                # regressed rule wrongly accepts the preceding candidate.
                self.seed(f"presence/{self.a}", None)
                self.assertDenied("PUT", f"presence/{self.a}", self.at, self.position(seq=seq))

    def test_presence_shape_timestamp_and_box_are_checked(self):
        invalid = (
            self.position(at=1), self.position(extra=True), self.position(box=""),
            self.position(box="x" * 1025), self.position(box="invalid punctuation!" * 5),
            {"seq": 1, "at": NOW},
        )
        for number, value in enumerate(invalid):
            with self.subTest(case=number):
                self.seed(f"presence/{self.a}", None)
                self.assertDenied("PUT", f"presence/{self.a}", self.at, value)

    def test_fresh_member_cannot_be_removed_by_another_member(self):
        self.join(self.b, self.bt)
        self.assertAllowed("PUT", f"presence/{self.b}", self.bt, self.position())
        self.assertDenied("DELETE", f"presence/{self.b}", self.at)
        self.assertDenied("DELETE", f"members/{self.b}", self.at)

    def test_stale_member_cleanup_requires_membership(self):
        self.join(self.b, self.bt)
        old = int(time.time() * 1000) - 25 * 60 * 60 * 1000
        self.seed(f"members/{self.b}", {"joined": old})
        self.seed(f"presence/{self.b}", self.position(at=old))
        self.assertDenied("DELETE", f"presence/{self.b}", self.ct)
        self.assertAllowed("DELETE", f"presence/{self.b}", self.at)
        self.assertAllowed("DELETE", f"members/{self.b}", self.at)

    def test_legacy_closed_room_accepts_no_new_members_or_presence(self):
        self.seed("meta/closed", int(time.time() * 1000))
        self.assertDenied("PUT", f"members/{self.b}", self.bt, {"joined": NOW})
        self.assertDenied("PUT", f"presence/{self.a}", self.at, self.position())
        self.assertAllowed("GET", "meta", self.at)

    def test_creator_leaves_group_stays_and_last_member_removes_room(self):
        self.join(self.b, self.bt)
        self.assertAllowed("DELETE", f"presence/{self.a}", self.at)
        self.assertAllowed("DELETE", f"members/{self.a}", self.at)
        self.assertDenied("GET", "presence", self.at)
        self.assertDenied("DELETE", "meta", self.at)
        self.assertAllowed("PUT", f"presence/{self.b}", self.bt, self.position())
        self.assertAllowed("DELETE", f"presence/{self.b}", self.bt)
        self.assertAllowed("DELETE", f"members/{self.b}", self.bt)
        self.assertAllowed("DELETE", "meta", self.bt)


if __name__ == "__main__":
    unittest.main(verbosity=2)
