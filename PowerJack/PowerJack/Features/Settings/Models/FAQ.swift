//
//  FAQ.swift
//  PowerJack
//

import Foundation

// The questions and answers shown under Settings > FAQ, grouped by topic.
struct FAQ {
    struct Topic: Hashable {
        let title: String
        let entries: [Entry]
    }

    struct Entry: Hashable {
        let question: String
        let paragraphs: [String]
        var sources: [Source] = []
    }

    struct Source: Hashable {
        let title: String
        let url: URL
    }
}

extension FAQ {
    static let topics: [Topic] = [
        Topic(title: "About PowerJack", entries: [
            Entry(
                question: "Really, another workout app?",
                paragraphs: [
                    "PowerJack does a few things that set it apart:",
                    "• It's free. Not just the app, but the code too, for anyone who wants it.",
                    "• It's fully private. No tracking, no ads, no social media. Everything stays on your device.",
                    "• It's built for resistance training. PowerJack is designed to make you work hard lifting heavy things, so you get stronger and grow bigger muscles.",
                ]
            ),
            Entry(
                question: "Why the name PowerJack?",
                paragraphs: [
                    "The technical term for \"getting jacked\", or growing larger muscles, is hypertrophy. Powerlifting is about building strength, usually for the three competition lifts: squat, bench press and deadlift.",
                    "Training for hypertrophy and training for strength overlap, but each can be optimized toward its own goal. Wanting to get both bigger and stronger is, in bro-science terms, PowerJacking.",
                    "Version 1 of PowerJack focuses on hypertrophy only. Later versions will add options for strength training, and for PowerJacking somewhere in the middle.",
                ]
            ),
        ]),
        Topic(title: "Training", entries: [
            Entry(
                question: "What's the difference between hypertrophy and strength?",
                paragraphs: [
                    "Strength training is about how much force you can produce. Hypertrophy training is about building more muscle mass.",
                    "In general, a bigger muscle can produce more force. But strength can also go up without much new muscle, because strength is also a skill: how well your nervous system recruits and coordinates muscle for a specific lift.",
                    "That's why new lifters often get much stronger in their first weeks, before their muscles have visibly grown, and why a smaller lifter who has practiced a lift for years can out-lift a bigger one who hasn't.",
                ]
            ),
            Entry(
                question: "What does strength training look like?",
                paragraphs: [
                    "Using your muscles close to their maximum force output. That usually means heavy weights, often 80% or more of your one-rep max, for low reps, traditionally 1 to 5 a set.",
                    "Heavy loads build strength best. Light and heavy loads build similar amounts of muscle, but heavy loads build more one-rep-max strength.",
                    "Strength is specific. You get strongest at the lifts, rep ranges and techniques you actually practice, so powerlifters train the squat, bench and deadlift themselves rather than only similar exercises.",
                    "Rest longer between heavy sets. Trained lifters who rested 3 minutes between sets gained more strength, and more muscle, than those who rested 1 minute.",
                    "You don't have to grind to failure. How close you stop to failure has little effect on strength gains, while it matters more for muscle growth, so heavy sets can stop about 3 to 5 reps short.",
                    "Practice the lift often. Training a lift more times per week tends to add strength, with diminishing returns, while for muscle growth the total number of hard sets matters more than how they are spread across the week.",
                ],
                sources: [
                    Source(
                        title: "Schoenfeld 2017: low vs high loads",
                        url: URL(string: "https://doi.org/10.1519/JSC.0000000000002200")!
                    ),
                    Source(
                        title: "Schoenfeld 2021: the repetition continuum",
                        url: URL(string: "https://doi.org/10.3390/sports9020032")!
                    ),
                    Source(
                        title: "Currier 2023: loads and sets for strength",
                        url: URL(string: "https://doi.org/10.1136/bjsports-2023-106807")!
                    ),
                    Source(
                        title: "Schoenfeld 2016: longer rest periods",
                        url: URL(string: "https://doi.org/10.1519/JSC.0000000000001272")!
                    ),
                    Source(
                        title: "Robinson 2024: proximity to failure",
                        url: URL(string: "https://doi.org/10.1007/s40279-024-02069-2")!
                    ),
                    Source(
                        title: "Pelland 2026: weekly volume and frequency",
                        url: URL(string: "https://doi.org/10.1007/s40279-025-02344-w")!
                    ),
                ]
            ),
            Entry(
                question: "What does hypertrophy training look like?",
                paragraphs: [
                    "Taking your muscles near failure. Muscle grows from sets anywhere between about 5 and 30 reps, as long as the sets are hard, and growth goes up with the number of hard sets you do for a muscle each week. Sets should end within about 5 reps of failure (0 to 5 RIR). Stopping closer to failure tends to give more growth per set, though exactly how much is uncertain, and it is harder to recover from.",
                    "It takes very little to maintain a muscle. Younger lifters have held on to their size for months with one hard set per exercise once a week, as long as the weight stayed heavy. Older lifters may need 2 to 3 sets, twice a week.",
                    "Measurable growth typically starts around 4 sets a week. From there, more weekly sets generally mean more growth, but each added set gives less than the one before.",
                    "When you count sets, work where a muscle only assists, like your biceps in a row, can be approximated as roughly half a set.",
                    "These are averages. Your body might need more or less, and it depends on where you are in your lifting journey: advanced lifters put on mass more slowly. Very high volumes are not a shortcut: in one study, trained lifters who built up to 52 quad sets a week did not grow significantly more than lifters who stayed at 22.",
                ],
                sources: [
                    Source(
                        title: "Schoenfeld 2017: weekly volume and growth",
                        url: URL(string: "https://doi.org/10.1080/02640414.2016.1210197")!
                    ),
                    Source(
                        title: "Schoenfeld 2021: the repetition continuum",
                        url: URL(string: "https://doi.org/10.3390/sports9020032")!
                    ),
                    Source(
                        title: "Robinson 2024: proximity to failure",
                        url: URL(string: "https://doi.org/10.1007/s40279-024-02069-2")!
                    ),
                    Source(
                        title: "Pelland 2026: weekly volume and frequency",
                        url: URL(string: "https://doi.org/10.1007/s40279-025-02344-w")!
                    ),
                    Source(
                        title: "Spiering 2021: the minimal dose to maintain",
                        url: URL(string: "https://doi.org/10.1519/JSC.0000000000003964")!
                    ),
                    Source(
                        title: "Enes 2024: very high weekly set counts",
                        url: URL(string: "https://doi.org/10.1249/MSS.0000000000003317")!
                    ),
                ]
            ),
            Entry(
                question: "What is RIR?",
                paragraphs: [
                    "Reps in reserve: how many more reps you could have done.",
                    "Say someone offered you $1,000 for every pushup you can do. You'd keep going until your arms gave out. If you managed 20 pushups with good form, then stopping at 20 is 0 RIR, or failure, and stopping at 17 is 3 RIR.",
                ]
            ),
            Entry(
                question: "How important is form?",
                paragraphs: [
                    "Our philosophy is simple. Bad form recruits muscles you didn't intend to train (like swinging your hips to get the last rep of a curl) and can raise your odds of injury. There is no place for bad form in the gym.",
                ]
            ),
            Entry(
                question: "How do I get close to failure without cheating my form?",
                paragraphs: [
                    "Failure isn't total muscle failure, it's form failure. If you can't do the lift as intended, you've already failed, and whatever happens next is cheating. There are no heroes in the gym.",
                ]
            ),
            Entry(
                question: "But PowerJack is all about \"no pain, no gain\", right?",
                paragraphs: [
                    "That's a bad saying. If you're training through pain, stop and see a medical provider. Don't mess with soft tissue: it heals slowly and it hurts.",
                    "That said, training with intensity and pushing through hard workouts is critical. If you can't tell the difference between a hard workout and pain, work with a trainer or coach.",
                ]
            ),
            Entry(
                question: "Any other tips?",
                paragraphs: [
                    "Consistency is king, and there's no way around it. Three days a week in the gym for years is far more effective than five days a week on and off.",
                ]
            ),
        ]),
        Topic(title: "Body and Nutrition", entries: [
            Entry(
                question: "Okay, but I just want to get toned…",
                paragraphs: [
                    "\"Toned\" isn't a thing. How toned you look comes from how much fat and how much muscle you have in an area, and that depends heavily on your body.",
                    "In most cases, getting toned is some combination of losing fat and building muscle, which is hypertrophy training.",
                ]
            ),
            Entry(
                question: "So I'll lose weight lifting?",
                paragraphs: [
                    "You can't out-exercise a bad diet. On its own, lifting trims a little fat, about 1.5 percentage points of body fat on average across studies, but it won't move the scale much. Substantial weight loss takes a sustained calorie deficit, and changing what you eat is usually the most practical way to create one.",
                    "Lifting while you diet helps you keep your muscle, so more of what you lose is fat.",
                ],
                sources: [
                    Source(
                        title: "Wewege 2022: resistance training and body fat",
                        url: URL(string: "https://doi.org/10.1007/s40279-021-01562-2")!
                    ),
                ]
            ),
            Entry(
                question: "I'm still going to eat lots of protein to get big.",
                paragraphs: [
                    "Cool. The old bro-science rule of 1 g of protein per pound of body weight a day is actually pretty close. On average, the benefit for muscle levels off around 0.7 g per pound (1.6 g/kg) a day. People vary, so 1 g per pound (2.2 g/kg) is a sensible upper end, and beyond that there is little evidence of extra muscle. The exception is dieting hard while already lean, like the weeks before a bodybuilding show, when more protein may help you hold on to muscle.",
                    "Training for strength needs about the same. Strength gains level off around 0.7 g per pound (1.5 g/kg) a day.",
                ],
                sources: [
                    Source(
                        title: "Morton 2018: protein and muscle gains",
                        url: URL(string: "https://doi.org/10.1136/bjsports-2017-097608")!
                    ),
                    Source(
                        title: "Nunes 2022: protein and lean mass",
                        url: URL(string: "https://doi.org/10.1002/jcsm.12922")!
                    ),
                    Source(
                        title: "Tagawa 2022: protein and strength gains",
                        url: URL(string: "https://doi.org/10.1186/s40798-022-00508-w")!
                    ),
                    Source(
                        title: "Refalo 2025: protein while dieting",
                        url: URL(string: "https://doi.org/10.1519/SSC.0000000000000888")!
                    ),
                ]
            ),
            Entry(
                question: "How important are supplements?",
                paragraphs: [
                    "Mostly, they aren't. Get what you need from a rich diet.",
                ]
            ),
            Entry(
                question: "Well, creatine is good, right?",
                paragraphs: [
                    "Creatine monohydrate does help in the gym. With a daily dose, lifters gain about 1 kg (2 lb) more lean mass on average than lifters training without it. Some of that is water held in the muscle: when muscle size is measured directly, the extra growth is real but small.",
                ],
                sources: [
                    Source(
                        title: "Delpino 2022: creatine and lean mass",
                        url: URL(string: "https://doi.org/10.1016/j.nut.2022.111791")!
                    ),
                    Source(
                        title: "Burke 2023: creatine and measured muscle size",
                        url: URL(string: "https://doi.org/10.3390/nu15092116")!
                    ),
                ]
            ),
            Entry(
                question: "Then beta-alanine is super important.",
                paragraphs: [
                    "Not really. For many people it causes a harmless tingling of the skin, which people take as a sign that \"it's working\". The tingle is a side effect, not the benefit. Any benefit comes from taking it daily for weeks, not from the scoop before your workout.",
                    "At best, it helps a little with all-out efforts lasting roughly 1 to 10 minutes. Most sets in the gym are over well before that, and an effect on strength hasn't been established.",
                ],
                sources: [
                    Source(
                        title: "Trexler 2015: ISSN position stand on beta-alanine",
                        url: URL(string: "https://doi.org/10.1186/s12970-015-0090-y")!
                    ),
                    Source(
                        title: "Georgiou 2024: beta-alanine and maximal efforts",
                        url: URL(string: "https://doi.org/10.1123/ijsnem.2024-0027")!
                    ),
                ]
            ),
            Entry(
                question: "Then why do I lift so much better on pre-workout?",
                paragraphs: [
                    "Caffeine. It gives a small but real boost to strength and power. High doses were on the Olympic banned list until 2004, and the NCAA still caps how much athletes can have in their system. In most pre-workouts, it's the ingredient doing the heavy lifting.",
                    "We'll let you decide whether you need it. Caffeine lingers: a typical pre-workout serving (about 200 mg) can cut into your sleep even when you take it 13 hours before bed. And remember: gains don't happen in the gym, they happen while you recover, and sleep is a big part of that. In one small study, a full night without sleep cut muscle protein synthesis by 18%.",
                ],
                sources: [
                    Source(
                        title: "Grgic 2018: caffeine, strength and power",
                        url: URL(string: "https://doi.org/10.1186/s12970-018-0216-0")!
                    ),
                    Source(
                        title: "USADA: caffeine's status in sport",
                        url: URL(string: "https://www.usada.org/spirit-of-sport/substance-profile-caffeine/")!
                    ),
                    Source(
                        title: "NCAA: banned substances list",
                        url: URL(string: "https://www.ncaa.org/sports/2015/6/10/ncaa-banned-substances.aspx")!
                    ),
                    Source(
                        title: "Gardiner 2023: caffeine and sleep",
                        url: URL(string: "https://doi.org/10.1016/j.smrv.2023.101764")!
                    ),
                    Source(
                        title: "Lamon 2021: sleep loss and muscle protein synthesis",
                        url: URL(string: "https://doi.org/10.14814/phy2.14660")!
                    ),
                ]
            ),
        ]),
    ]
}
