# ANTHROFIT

An Android app that measures body segment proportions and estimates body composition with the phone camera, then builds a personalised resistance-training program for Filipino adult gym users.

Capstone project, Cagayan State University – Carig Campus, College of Information and Computing Sciences.
Developed by Lord Benedict D. Cabocan, Janusz Gwynn B. Saquing and Jayro M. Cuntapay.

> Not a medical device. Scan results are camera estimates, not measurements, and no feature has been clinically validated.

---

## The core loop

**Scan → generate program → work out → scan again → see progress**

1. **Body proportion scan** (MediaPipe Pose): limb and trunk ratios that shape which exercises are recommended.
2. **Body composition scan** (front and side outlines, height, weight, age, sex): body fat with an 80% range, fat-free mass. Drives the training goal and nutrition targets.
3. **Generate my program**: a personalised plan from the scans and the profile.
4. **Work out**: log sets, rest timer, coaching, guided sets with camera rep counting.
5. **Save and scan body composition** after a workout: the result shows what changed since the last scan, with a detailed comparison and the Progress screen one tap away.

## Features

- **Profile and onboarding**: goal, experience, schedule, equipment, PAR-Q+ health questions, injuries, food preferences; kg or lb.
- **Scans**: guided session (proportions + composition), or either on its own; height and weight check before scanning; scan history, comparisons and trends in Body analysis and Progress. Scan photos are kept in original colour on the phone; model input is processed separately.
- **Programs**: personalised plan, ready-made programs, plan-based or freestyle creation, weekly schedule, program review.
- **Workouts**: session logging, warm-up and cool-down prompts, rest timer with notification, set coaching (AI rewording of rule-based findings via Firebase AI Logic), guided sets with camera rep counter, workout history (delete a workout or one exercise).
- **Progress**: strength, muscle distribution, body weight, body composition trends, **progress photos** (colour photos by date, compare any two).
- **Nutrition**: daily targets from the profile and latest composition estimate; example Filipino meals (Pinggang Pinoy proportions).
- **Community** (friends only): share progress, an exercise, body composition or progress photos with a text post; kudos (with names) and comments; friend requests, blocking, reports, inbox.
- **Reminders**: training-day notifications.
- **Admin web panel**: add or hide exercises and equipment, edit workout templates, ready-made programs, ranking weights, goal fit, proportion cut-offs and rules. Phones pick up changes at start-up.

## Tech stack

| Part | Used |
|---|---|
| App | Flutter (Dart ≥ 3.8), Android |
| Pose | MediaPipe Pose Landmarker (Kotlin, `PoseLandmarkerHelper.kt`, `PosePreviewFactory.kt`) |
| Backend | Firebase Authentication, Cloud Firestore, App Check, Firebase AI Logic (Gemini Flash-Lite) |
| Local storage | SharedPreferences, app files (scan visuals, progress photos) |
| Key packages | `cloud_firestore`, `firebase_auth`, `firebase_ai`, `firebase_app_check`, `shared_preferences`, `path_provider`, `permission_handler`, `fl_chart`, `flutter_local_notifications`, `timezone`, `image_picker`, `image` |

The Firebase project is on the free Spark plan, so there is no Cloud Storage: shared photos are stored as small JPEGs in Firestore.

## Project layout

```text
lib/
  admin/            admin web panel (separate entry point: admin_main.dart)
  auth/             sign-in, accounts, guest mode
  cloud/            Firestore sync for user data
  coaching/         set coach, warm-up/cool-down, program review, tutorials
  community/        posts, friends, sharing (models, service, builders)
  composition/      body composition estimate and scan visuals
  content/          admin content read by the app (exercises, equipment, settings)
  data/             exercise library, templates, repositories
  intelligence/     AI explainer (Gemini), with reply checks
  legal/            Terms and Privacy text
  models/           data models
  notifications/    rest alerts and reminders
  nutrition/        targets and example meals
  photos/           progress photo records
  progress/         analytics and trends
  recommendation/   program recommender, scorer, proportion rules, weights
  reps/             camera rep counter
  scan/             proportion scan bridge, camera permission
  screens/          UI
  state/            controllers and scopes
android/app/src/main/kotlin/...   MediaPipe and camera code
android/app/src/main/assets/      pose_landmarker_full.task (and optionally _lite)
firestore.rules                   security rules
test/                             unit and widget tests
```

## Setup

1. Install Flutter (stable) and Android Studio.
2. Get packages:
   ```
   flutter pub get
   ```
3. Firebase: `flutterfire configure` for **android** and **web** (web is needed for the admin panel). Enable Email/Password sign-in and Firestore.
4. Publish `firestore.rules` in Firebase console → Firestore → Rules.
5. Firestore indexes: create any index the console asks for (the feed query uses `audience` + `createdAt`).
6. Optional, faster rep counting: put `pose_landmarker_lite.task` (from the MediaPipe Pose Landmarker models page) in `android/app/src/main/assets/`. Without it the counter uses the full model.
7. App Check uses the debug provider for development (see `main.dart`); switch to Play Integrity before release.

## Run

Phone app:
```
flutter run
```

Admin panel (in a browser):
```
flutter run -d edge -t lib/admin/admin_main.dart
```
or `-d chrome`, or `-d web-server --web-port 8080` and open `http://localhost:8080`.

To make an account an admin: Firestore → collection `admins` → document ID = the account's user ID (the panel shows it), with any field, e.g. `name`.

## Tests

```
flutter analyze
flutter test
```

`test/flutter_test_config.dart` turns off the warm-up/cool-down cards and Firebase content fetching for all tests. Tests check app logic on made-up data; they say nothing about real-world accuracy (for example, rep counts must be validated against manual counts).

## Sources and design choices

The app's screens do not name studies or organisations; the sources behind its numbers are listed here instead. Code comments next to each value give the details.

### Training

- **Sets, reps, rest and weekly frequency** (the "strength", "muscle-building" and "power" models, and the suggested days a week per experience level): American College of Sports Medicine (2009). Position stand: Progression models in resistance training for healthy adults. *Med Sci Sports Exerc* 41(3):687–708. Experience levels (beginner, intermediate, advanced) follow the same paper. Cardio length is not covered by it and is an app choice.
- **Warm-up and cool-down** (5–10 minutes of light activity, stretches held 10–30 s): Garber, C. E., et al. (2011). ACSM position stand: Quantity and quality of exercise. *Med Sci Sports Exerc* 43(7):1334–1359.
- **Weekly sets per muscle** (reading only, no target enforced): Schoenfeld, B. J., Ogborn, D., & Krieger, J. W. (2017). Dose-response relationship between weekly resistance training volume and increases in muscle mass. *J Sports Sci* 35(11):1073–1082.
- **Calories burned in a workout**: Herrmann, S. D., et al. (2024). 2024 Adult Compendium of Physical Activities, code 02054 (resistance training, 8–15 reps) = 3.5 METs.

### Health screening

- **Health questions**: PAR-Q+ Collaboration. The Physical Activity Readiness Questionnaire for Everyone (PAR-Q+), 2023 edition. The seven questions are used word for word. Anyone answering YES can complete the PAR-Q+ follow-up questions at [eparmedx.com](https://eparmedx.com).
- **When to see a doctor first** (chest pain, dizziness or fainting, supervised-only exercise): Riebe, D., et al. (2015). Updating ACSM's recommendations for exercise preparticipation health screening. *Med Sci Sports Exerc* 47(11):2473–2479.

### Body composition

- **Estimation models**: Rishab CV (2026), body composition models, MIT License (`assets/composition/LICENSE-bodycomp.txt`). Trained on US adults aged 18–59 (NHANES, with DXA scans as the reference). The source reports a bias of about 1.4 body fat points for people of Asian descent.
- **80% range**: conformal prediction intervals bundled with the models; on the models' test set the true value fell inside the range for 79.4% of people (body fat mean absolute error 2.7 points).
- **Body fat ranges** (Essential, Athletes, Fitness, Average, Obese): American Council on Exercise (ACE) body fat categories.

### Nutrition

- **Resting energy, no scan**: Mifflin, M. D., St Jeor, S. T., et al. (1990). *Am J Clin Nutr* 51:241–247.
- **Resting energy, with a scan**: Katch-McArdle equation (370 + 21.6 × fat-free mass).
- **Activity levels**: FAO/WHO/UNU (2004). Human Energy Requirements, Table 5.3 (PAL ranges).
- **Calorie surplus** (10–20% above maintenance): Iraki, J., et al. (2019). Nutrition recommendations for bodybuilders in the off-season. *Sports* 7(7):154.
- **Calorie deficit, higher body fat** (500–750 kcal a day): Jensen, M. D., et al. (2013). AHA/ACC/TOS Guideline for the Management of Overweight and Obesity in Adults.
- **Calorie deficit, leaner** (0.5–1% of body weight a week): Helms, E. R., Aragon, A. A., & Fitschen, P. J. (2014). *J Int Soc Sports Nutr* 11:20. Converted with ~7,700 kcal per kg lost (Wishnofsky, 1958), an approximation.
- **Protein**: Jäger, R., et al. (2017). ISSN position stand: protein and exercise. *J Int Soc Sports Nutr* 14:20 (1.4–2.0 g/kg). With a scan and a fat-loss goal: Aragon, A. A., et al. (2017). ISSN position stand: diets and body composition. *J Int Soc Sports Nutr* 14:16 (2.3–3.1 g/kg of fat-free mass).
- **Fat**: Institute of Medicine (2005). Dietary Reference Intakes, AMDR: 20–35% of energy. Carbohydrate is the rest.
- **Plate guide** (½ vegetables and fruit, ⅓ grains, ⅙ protein): FNRI-DOST Pinggang Pinoy.

### Camera

- **Pose landmarks**: Google MediaPipe Pose Landmarker.
- **Rep counter smoothing**: Casiez, G., Roussel, N., & Vogel, D. (2012). 1€ filter: a simple speed-based low-pass filter for noisy input in interactive systems. *Proc. CHI 2012*, 2527–2530.

### App design choices

Values that do **not** come from a published source:

- Body proportion cut-offs come from this project's own measured participants (median split for femur:torso and arm:torso; Q1/Q3 for upper body:stature and shoulder:hip). There is no published reference for a long or short limb.
- Ranking weights, goal-fit heuristic, proportion rule nudges, template contents, rep counter tuning, timers, photo sizes and similar numbers are app design choices.

Every assumption and limitation is listed in the project's design-assumptions document.

## Privacy

- Guest mode keeps everything on the phone. With an account, profile, programs, workouts and scan results sync to Firebase.
- Scan outlines and scan photos stay on the phone. Progress photos stay on the phone unless picked for a Community post, which uploads a smaller copy that only friends can see and that is deleted with the post.
- Body composition numbers are shared only when ticked for a post.
- The AI coach receives only the app's own findings, goal and experience level, never names, emails, photos or full history.
- Video is never recorded.
