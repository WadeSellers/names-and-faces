# V2 privacy changes — do these at submission, not before

1.0 collects nothing. V2's **share by code** sends a deck to a server, so the
App Privacy answers and the privacy policy both have to change *when V2 is
submitted*. The policy stays as-is until then; it is accurate for 1.0.

Sharing **as a file** does not touch the server and changes nothing.

## App Store Connect → App Privacy

Data collection: **Yes**. For each type below: *not linked to the user's
identity*, *not used for tracking*, purpose **App Functionality** only.

| Type | Why |
|---|---|
| Photos or Videos | Portraits in a deck shared by code |
| Other User Content | Names in a deck shared by code |
| Device ID | A random ID made on the phone, used only to count wrong code guesses per phone |

Device ID is a judgment call — it is a random per-install UUID, not an
advertising or hardware identifier. Declaring it is the conservative answer.

## Privacy policy — add this section

> **Sharing a deck with a code.** If you choose *Get a Code*, the deck — its
> portraits and names — is uploaded to a server we run so that someone who
> types the code can download it. It is not tied to your name, email, or any
> account, because there are none. The deck is deleted automatically after
> 30 days, or immediately when you tap *Stop Sharing*. To limit guessing, the
> server keeps a count of wrong codes for each phone (using a random ID the
> app creates) and for each network address, and discards those counts within
> an hour.
>
> **Sharing a deck as a file** sends it directly by AirDrop, Messages, Mail, or
> Files, and never passes through our server.

And change the opening line, which currently says the app talks to no server.

## Server

`ntf-codes` Cloudflare Worker, `https://ntf-codes.wadesellers.workers.dev`.
KV namespace `DECKS` (730814c52d80430bb7792738a005f773). Every deck is written
with a 30-day TTL, so nothing outlives that even if Stop Sharing is never used.
