# Apple purchase trust roots

Public root CA certificates downloaded October 8, 2026 from [Apple PKI](https://www.apple.com/certificateauthority/). They are public verification material, not signing keys. The local ignored `.env` points to these files and uses `APPLE_ENVIRONMENT=Sandbox`.

| File | Official source | Expires (UTC) |
|---|---|---|
| AppleIncRootCertificate.cer | https://www.apple.com/appleca/AppleIncRootCertificate.cer | February 9, 2035 |
| AppleRootCA-G2.cer | https://www.apple.com/certificateauthority/AppleRootCA-G2.cer | April 30, 2039 |
| AppleRootCA-G3.cer | https://www.apple.com/certificateauthority/AppleRootCA-G3.cer | April 30, 2039 |

Each certificate's CA flag, self-signature and expiry were checked before installation. Apple's official server library performs transaction signature, certificate chain, online revocation, environment and bundle validation. This configuration does not verify that App Store products are available or that a genuine purchase completes successfully. Production verification additionally requires the app's numeric App Store ID and the Production environment setting.
