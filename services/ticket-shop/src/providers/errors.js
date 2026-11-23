// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

/** A provider refused or failed. `message` is safe to show (no keys, no customer data). */
export class ProviderError extends Error {
  constructor(provider, status, message) {
    super(message);
    this.provider = provider;
    this.status = status;
  }
}
