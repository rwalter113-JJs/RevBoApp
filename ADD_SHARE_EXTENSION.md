# Adding Share Extension to RevBo

The code is ready! Now you need to add the target in Xcode:

## Step 1: Add Share Extension Target

1. Open `RevBoApp.xcodeproj` in Xcode
2. File → New → Target
3. Choose **iOS** → **Share Extension**
4. Click **Next**
5. Product Name: `RevBoShareExtension`
6. Organization Identifier: `com.robwalter`
7. Bundle Identifier should auto-fill to: `com.robwalter.revbo.RevBoShareExtension`
8. **UNCHECK** "Embed in Application" (we'll set this manually)
9. Click **Finish**
10. When asked "Activate 'RevBoShareExtension' scheme?", click **Activate**

## Step 2: Replace Generated Files

Xcode creates default files. Replace them with ours:

1. In the Project Navigator, **delete** these auto-generated files:
   - `RevBoShareExtension/ShareViewController.swift` (the default one)
   - `RevBoShareExtension/Info.plist` (if it created one)
   
2. **Add our files** by dragging them from Finder into the `RevBoShareExtension` folder:
   - `RevBoShareExtension/ShareViewController.swift` (already created)
   - `RevBoShareExtension/Info.plist` (already created)

3. When adding, ensure:
   - ✅ "Copy items if needed" is UNCHECKED (files are already in the right place)
   - ✅ "Add to targets" has **RevBoShareExtension** checked
   - ✅ "Create groups" is selected

## Step 3: Configure App Groups

Both the main app and the Share Extension need to share data via App Groups.

### Main App Target (RevBoApp):
1. Select **RevBoApp** target
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability**
4. Add **App Groups**
5. Click **+** under App Groups
6. Add: `group.com.robwalter.revbo`
7. Ensure it's **checked**

### Share Extension Target (RevBoShareExtension):
1. Select **RevBoShareExtension** target
2. Go to **Signing & Capabilities** tab
3. Click **+ Capability**
4. Add **App Groups**
5. Click **+** under App Groups
6. Add: `group.com.robwalter.revbo` (same as main app)
7. Ensure it's **checked**

## Step 4: Configure Share Extension Settings

1. Select **RevBoShareExtension** target
2. **General** tab:
   - Deployment Info → iOS 17.0 (match main app)
   - Frameworks, Libraries: Should be empty (extension is lightweight)

3. **Build Settings** tab:
   - Search for "Swift Language Version" → Swift 5
   - Search for "iOS Deployment Target" → iOS 17.0

4. **Info** tab (or Info.plist):
   - Verify `NSExtensionActivationRule` has:
     - `NSExtensionActivationSupportsImageWithMaxCount` = 1
   - Verify `NSExtensionPrincipalClass` = `$(PRODUCT_MODULE_NAME).ShareViewController`

## Step 5: Embed Extension in Main App

1. Select **RevBoApp** target (main app)
2. Go to **General** tab
3. Scroll to **Frameworks, Libraries, and Embedded Content** section
4. Below that, find **Embedded Binaries** or **Embed App Extensions**
5. Click **+**
6. Select **RevBoShareExtension.appex**
7. Ensure it shows as "Embed & Sign"

Alternative location:
- **Build Phases** tab
- Find or add **Embed App Extensions** phase
- Add `RevBoShareExtension.appex`

## Step 6: Build and Test

1. Select **RevBoApp** scheme (not RevBoShareExtension)
2. Build: Cmd+B
3. Run on device or simulator
4. Take a screenshot or open Photos
5. Tap **Share** button
6. Scroll horizontally in the share sheet
7. You should see **RevBo** icon!

If you don't see it:
- Scroll all the way to the right
- Tap "Edit Actions" or "..."
- Enable RevBo extension

## Step 7: Archive for Distribution

When ready for TestFlight:

1. Archive the **RevBoApp** target (Product → Archive)
2. The Share Extension will automatically be included
3. Upload to TestFlight normally

---

## Troubleshooting

**"App Groups not showing"**
- Make sure you're signed in to the same Apple Developer account in Xcode Preferences
- Try toggling "Automatically manage signing" off and on

**"Extension not appearing in share sheet"**
- Extensions only appear for content types they support
- Our extension only shows for images
- Try sharing from Photos app with an actual image

**"Build fails with duplicate symbols"**
- Make sure RevBoShareExtension doesn't link against the main app target
- Extension should be standalone

**"Share Extension crashes on launch"**
- Check that App Group name matches exactly: `group.com.robwalter.revbo`
- Verify Info.plist has correct NSExtensionPrincipalClass
