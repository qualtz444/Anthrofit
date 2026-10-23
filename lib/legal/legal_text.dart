// The Terms of Service and Privacy Policy shown at sign-up and from Profile.
//
// DRAFT written from what the app actually does. It is not legal advice and
// has not been reviewed by a lawyer or an ethics board. Before real users
// sign up, fill in [kLegalContact], check it against the Data Privacy Act of
// 2012 (Republic Act No. 10173) and your adviser's or ethics committee's
// requirements, and update [kLegalUpdated].

/// Who to contact about data. Fill in before release.
const String kLegalContact = '[your contact email]';

/// When the text below last changed.
const String kLegalUpdated = 'October 14, 2026';

class LegalSection {
  const LegalSection(this.heading, this.body);
  final String heading;
  final String body;
}

class LegalDocument {
  const LegalDocument({required this.title, required this.sections});
  final String title;
  final List<LegalSection> sections;
}

const LegalDocument kTermsOfService = LegalDocument(
  title: 'Terms of Service',
  sections: [
    LegalSection(
      'What ANTHROFIT is',
      'ANTHROFIT is a student capstone project. It suggests resistance '
          'training programs, estimates body proportions and body '
          'composition from your phone camera, and tracks your workouts. '
          'It is for general fitness only.',
    ),
    LegalSection(
      'Not medical advice',
      'ANTHROFIT is not a medical device and does not diagnose, treat or '
          'prevent any condition. Body measurements and body composition '
          'are camera estimates with a margin of error, not clinical '
          'measurements. Talk to a doctor before starting exercise if the '
          'health questions in the app suggest it, or if you have any '
          'doubt. Stop exercising and get help if you feel pain, dizziness '
          'or chest discomfort.',
    ),
    LegalSection(
      'Training at your own risk',
      'Programs, sets, reps, weights and coaching tips are suggestions. You '
          'decide what you lift and how. Use safe technique, a spotter where '
          'needed, and weights you can control.',
    ),
    LegalSection(
      'Your account',
      'Keep your password private. You can use the app as a guest without '
          'an account; then your data stays on this phone only.',
    ),
    LegalSection(
      'Community',
      'Only share what you are comfortable with friends seeing. Be '
          'respectful. Do not post anything offensive, false or someone '
          "else's private information. You can report or block other "
          'users. Posts that break these rules may be removed.',
    ),
    LegalSection(
      'AI explanations',
      'Some explanations are written by an AI model from findings the app '
          'has already worked out. They can be wrong or incomplete; the '
          "app's own numbers are what it uses.",
    ),
    LegalSection(
      'Changes',
      'These terms may change as the project develops. The date at the top '
          'shows the latest version.',
    ),
    LegalSection('Contact', 'Questions: $kLegalContact'),
  ],
);

const LegalDocument kPrivacyPolicy = LegalDocument(
  title: 'Privacy Policy',
  sections: [
    LegalSection(
      'What the app stores',
      'Account: your name, email and date of birth.\n'
          'Profile: sex, height, weight, goals, training experience and '
          'frequency, equipment, daily routine, your answers to the health '
          'questions (PAR-Q+), injuries you note, and food preferences or '
          'allergies.\n'
          'Training: your programs and the workouts you log.\n'
          'Scans: body proportion ratios and body composition estimates.',
    ),
    LegalSection(
      'The camera',
      'Body scans and the rep counter process the camera image on this '
          'phone. Video is never recorded or uploaded. A body composition '
          'scan saves your body outline, and the photos it takes, on this '
          'phone only. Progress photos you take or pick are also saved on '
          'this phone only. A selfie taken when you share from Progress is '
          'used for that post only and is not saved.',
    ),
    LegalSection(
      'Where your data is kept',
      'As a guest, everything stays on this phone. With an account, your '
          'profile, programs, workouts and scan results are also saved to '
          "Google's Firebase service, so they sync to your other devices. "
          'Scan outlines are never uploaded. A scan photo, progress photo or '
          'selfie is uploaded only when you share it in a post, as a smaller '
          'copy, and is deleted with the post.',
    ),
    LegalSection(
      'AI',
      'When the coach or an "Explain more" button uses AI, the app sends '
          'the findings it has worked out (for example "top weight rose from '
          '40 kg to 47.5 kg"), with your goal and experience level, to '
          "Google's Gemini model through Firebase. It never sends your name, "
          'email, photos, outlines or your full history.',
    ),
    LegalSection(
      'Community',
      'Friends can see your display name, username, and only the posts you '
          'choose to share. Body composition numbers are shared only when '
          'you tick them for a post, and progress photos only when you pick '
          'them for a post. Kudos and comments show your name to '
          "the post's viewers. Reports go to the project team for review.",
    ),
    LegalSection(
      'Notifications',
      'Rest alerts and workout reminders are set on this phone. Nothing is '
          'sent to a server to show them.',
    ),
    LegalSection(
      'Your choices',
      'You can edit your profile, delete scans, workouts and posts, remove '
          'friends, and turn reminders off at any time. To have your account '
          'and the data saved with it deleted, contact $kLegalContact.',
    ),
    LegalSection(
      'Who sees your data',
      'Only you, the friends you accept (for what you share), and the '
          'project team when needed to run or fix the app. Your data is not '
          'sold or used for advertising.',
    ),
    LegalSection('Contact', 'Questions about your data: $kLegalContact'),
  ],
);
