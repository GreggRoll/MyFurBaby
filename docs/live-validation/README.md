# Live GPT Image 2 validation

Generated October 8, 2026 using the configured server-side project key, medium quality, 1024×1024 PNG. JSON records contain provider usage and request identifiers; they contain no credentials.

- `pet.png`: direct provider creation, canonical reference for the following edits.
- `in-app-pet.png`: separate creation through the real app/backend flow. Naming and persistence succeeded; the wallet charged 250 trial credits.
- `cloud-pet.png`: creation through the deployed Railway HTTPS API. Charged exactly 250 credits, reused the same job on retry, and survived a live redeploy with the account and wallet. `cloud-validation.json` records these checks without account tokens.
- `sleep.png` / `lick.png`: reference-based four-frame sheets. Individual cell crops are included. These edits were tested directly; they do not establish working Apple purchases or automatic Home Screen animation.
- `photo-source.jpg`: resized public [NASA photograph of Buzz Aldrin on the Moon](https://science.nasa.gov/resource/buzz-aldrin-on-the-moon/). Credit: NASA.
- `photo-adventure.png`: **AI-edited demonstration**, adding the canonical puppy to that photograph. This is not a historical photograph. The edit used both the photo and pet as references. It validates the provider path, not the app's Pro purchase or a personal-photo upload.

| Request | Text input tokens | Image input tokens | Image output tokens |
|---|---:|---:|---:|
| Direct pet | 181 | 0 | 1,756 |
| In-app pet | 179 | 0 | 1,756 |
| Sleeping sheet | 266 | 1,024 | 1,756 |
| Licking sheet | 260 | 1,024 | 1,756 |
| Photo insertion | 174 | 2,506 | 1,756 |

App credits are product units, separate from provider tokens. These few requests are examples, not a forecast of average generation cost or quality across species.
