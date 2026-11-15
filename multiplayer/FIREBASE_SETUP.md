# Firebase Setup — what you need to do (about 2 minutes)

The online multiplayer needs a free Firebase account to run on. This is
Google's service that hosts the matchmaking and game data. You only have to
do this once — send me what comes out and I'll wire up the rest.

## Steps

1. Go to **console.firebase.google.com** and sign in with your Google
   account (the mzaras11@gmail.com one is fine).

2. Click **"Add project"** (or "Create a project").
   - Name it `swish-crossword-battle`.
   - When it asks about Google Analytics, you can turn it **off** — we
     don't need it.
   - Click **Create project** and wait for it to finish.

3. Once you're inside the project, click the **iOS icon** (it looks like an
   Apple logo) to add an iPhone app. It may be under "Add an app" or "Get
   started by adding Firebase to your app".

4. When it asks for the **iOS bundle ID**, type exactly:
   ```
   com.swishgame.app
   ```
   (Copy-paste it — it has to match perfectly. The "App nickname" can be
   anything, like `S.W.I.S.H`.)

5. Click through. Firebase will offer you a file to download called
   **GoogleService-Info.plist** — download it.

6. **Send that file to me** (in this chat). I'll put it in the right place
   in the project. Don't rename it.

That's it — you're done. The rest (databases, game rules on the server, push
notifications) is my job once I have that file.

## Notes

- Firebase has a free plan (called "Spark") and that's all we need to
  start. Don't enter any payment info.
- If you already have a Firebase project from something else, you can reuse
  it — just add the iOS app with the bundle ID above and send me the file.
- Keep the file private — it's tied to your project. Don't post it
  anywhere public.
