# Third-party notices

## ReviewX

ReviewX project code is Copyright (c) 2026 Chengeeker and is distributed under the MIT License in the repository root `LICENSE`, subject to the separate notices below.

## Components adapted from Review

ReviewX includes portions adapted from Review: the application theme and theme preferences, shared haptic helper, cached-image widget, bounded image-cache maintenance, settings cards/dialogs, and personalisation screens. Copyright (c) 2026 Chengeeker. The original MIT notice is preserved in `licenses/Review-MIT.txt`. Original project: https://github.com/Chengeeker/Review.

## X transaction-ID encoder and data

`lib/twitter/api/transaction_id.dart` is a Dart adaptation of the compact transaction-ID encoder in [`fa0311/x-client-transaction-id-generater`](https://github.com/fa0311/x-client-transaction-id-generater), version 0.0.7. Copyright (c) 2025 yuki. The upstream MIT notice is reproduced in `licenses/fa0311-transaction-mit.txt`.

`assets/x_transaction_pairs.json` is the public pair dataset from [`fa0311/x-client-transaction-id-pair-dict`](https://github.com/fa0311/x-client-transaction-id-pair-dict), commit `ce8b0a2a7fcbb9b8b0bf594a25344c9fc3a0c00d`. Copyright (c) 2025 yuki; the same MIT notice applies. The dataset is bundled with the app, so generating a request header does not make an extra network request.

## X protocol parameters

`assets/twitter_protocol.json` contains X API operation identifiers and request parameters. `tool/refresh_x_protocol.ps1` can refresh identifiers found in X's public first-party web bundle. Operations absent from the entry bundle retain their last pinned identifiers because X may load them only in a later/private route. These identifiers and request flags are protocol data, not bundled X client implementation code. X's private APIs can change without notice.

## Account and credential handling

The supported login flow is manual X Cookie entry and server-side session validation through X endpoints. No embedded X login WebView is included. Account cookies are not sent to GitHub or the transaction-pair data host. Never publish a real Cookie, password, or signing key in an issue, screenshot, log, or source change.

Flutter dependency license notices remain available in the application's license screen.
