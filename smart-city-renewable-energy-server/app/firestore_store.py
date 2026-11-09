from __future__ import annotations

import os
from typing import Any, Dict, Optional

try:
    from google.cloud import firestore
except Exception:  # pragma: no cover - optional dependency at runtime
    firestore = None


class FirestoreStore:
    def __init__(self) -> None:
        self._enabled_flag = _env_bool("FIRESTORE_ENABLED", default=False)
        self.project_id = os.getenv("FIRESTORE_PROJECT_ID") or os.getenv("GOOGLE_CLOUD_PROJECT")
        self._client = None
        self._error: Optional[str] = None

    @property
    def enabled(self) -> bool:
        return self._enabled_flag and firestore is not None and bool(self.project_id)

    @property
    def error(self) -> Optional[str]:
        return self._error

    def _client_or_none(self):
        if not self.enabled:
            return None
        if self._client is None:
            try:
                self._client = firestore.Client(project=self.project_id)
            except Exception as exc:  # pragma: no cover - depends on environment
                self._error = str(exc)
                return None
        return self._client

    def get_load_profile_assignment(self, device_id: str) -> Optional[Dict[str, Any]]:
        client = self._client_or_none()
        if client is None:
            return None
        try:
            doc = (
                client.collection("devices")
                .document(device_id)
                .collection("load_profile")
                .document("current")
                .get()
            )
        except Exception as exc:  # pragma: no cover - depends on environment
            self._error = str(exc)
            return None

        if not doc.exists:
            return None
        data = doc.to_dict() or {}
        data["device_id"] = device_id
        return data

    def save_load_profile_assignment(self, device_id: str, payload: Dict[str, Any]) -> bool:
        client = self._client_or_none()
        if client is None:
            return False
        try:
            (
                client.collection("devices")
                .document(device_id)
                .collection("load_profile")
                .document("current")
                .set(
                    {
                        **payload,
                        "assigned_at": firestore.SERVER_TIMESTAMP,
                    },
                    merge=True,
                )
            )
            return True
        except Exception as exc:  # pragma: no cover - depends on environment
            self._error = str(exc)
            return False

    def save_load_forecast(self, device_id: str, horizon_days: int, payload: Dict[str, Any]) -> bool:
        return self._save_nested_doc(
            device_id=device_id,
            collection="load_forecast",
            document=f"{horizon_days}d",
            payload=payload,
        )

    def save_energy_balance(self, device_id: str, payload: Dict[str, Any]) -> bool:
        return self._save_nested_doc(
            device_id=device_id,
            collection="energy_balance",
            document="latest",
            payload=payload,
        )

    def save_optimization(self, device_id: str, payload: Dict[str, Any]) -> bool:
        return self._save_nested_doc(
            device_id=device_id,
            collection="optimization",
            document="latest",
            payload=payload,
        )

    def _save_nested_doc(
        self,
        *,
        device_id: str,
        collection: str,
        document: str,
        payload: Dict[str, Any],
    ) -> bool:
        client = self._client_or_none()
        if client is None:
            return False
        try:
            (
                client.collection("devices")
                .document(device_id)
                .collection(collection)
                .document(document)
                .set(
                    {
                        **payload,
                        "created_at": firestore.SERVER_TIMESTAMP,
                    },
                    merge=True,
                )
            )
            return True
        except Exception as exc:  # pragma: no cover - depends on environment
            self._error = str(exc)
            return False


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}
