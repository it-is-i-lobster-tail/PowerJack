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
                    "In general, more muscle means more motor units to recruit, and so more force. But strength can also go up without much new muscle, because strength is also a skill: how efficiently your nervous system fires to recruit muscle for a task.",
                    "For example, a 225 lb bodybuilder might carry 10 lb of muscle on their chest but recruit it at only 50% efficiency. They would produce about the same force as a 180 lb powerlifter with 6 lb of chest muscle who, thanks to neural adaptation, recruits it far better.",
                ]
            ),
            Entry(
                question: "What does strength training look like?",
                paragraphs: [
                    "Using your muscles close to their maximum force output. That usually means lower reps, in the 2 to 8 range, with each set building in weight so the last set is the most force you can produce.",
                    "Heavy loads build strength best. Light and heavy loads build similar amounts of muscle, but heavy loads build more one-rep-max strength.",
                    "Strength is specific. You get strongest at the lifts, rep ranges and techniques you actually practice, so powerlifters train the squat, bench and deadlift themselves rather than only similar exercises.",
                    "Rest longer between heavy sets. Trained lifters who rested 3 minutes between sets gained more strength, and more muscle, than those who rested 1 minute.",
                    "You don't have to grind to failure. How close you stop to failure has little effect on strength gains, while it matters more for muscle growth, so heavy sets can stop a few reps short.",
                    "Practice the lift often. Training a lift more times per week tends to add strength, while for muscle growth the total number of hard sets matters more than how they are spread across the week.",
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
                        title: "Schoenfeld 2016: longer rest periods",
                        url: URL(string: "https://doi.org/10.1519/JSC.0000000000001272")!
                    ),
                    Source(
                        title: "Robinson 2024: proximity to failure",
                        url: URL(string: "https://www.fau.edu/newsdesk/articles/muscle-growth-strength-study")!
                    ),
                    Source(
                        title: "Pelland: weekly volume and frequency",
                        url: URL(string: "https://sportrxiv.org/index.php/server/preprint/view/460")!
                    ),
                ]
            ),
            Entry(
                question: "What does hypertrophy training look like?",
                paragraphs: [
                    "Taking your muscles near failure. Muscle grows from sets anywhere between 5 and 30 reps, and growth goes up with the number of hard sets you do for a muscle each week. Sets should end with 2 to 5 reps in reserve (RIR).",
                    "In general it takes only 2 to 3 sets a week to maintain a muscle. Growth typically starts around 4 sets a week, and from there each doubling of sets adds about half as much as the last. For example, for glutes:",
                    "• 2 sets of squats: maintenance, no change",
                    "• 4 sets of squats: 50% of potential growth",
                    "• 8 sets of squats: 75% of potential growth",
                    "• 16 sets of squats: 87.5% of potential growth",
                    "These are averages. Your body might need more or less, and it depends on where you are in your lifting journey: advanced lifters put on mass more slowly. Some research suggests even 50 sets a week can still build muscle. The point of the example is to show diminishing returns.",
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
                    "Our philosophy is simple. Bad form recruits muscles you didn't intend to train (like swinging your hips to get the last rep of a curl) and raises your odds of injury. There is no place for bad form in the gym.",
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
                    "You can't out-exercise a bad diet. Lifting is not a valid approach to losing body fat.",
                ]
            ),
            Entry(
                question: "I'm still going to eat lots of protein to get big.",
                paragraphs: [
                    "Cool. The old bro-science rule of 1 g of protein per pound of body weight a day is actually pretty close. About 0.7 g per pound a day is generally the sweet spot, going from 0.7 g to 1 g gives a modest boost, and beyond 1 g the benefit is little to none unless you have a specific short-term goal, like a bodybuilding show a few weeks out.",
                    "Training for strength needs a little less than training for hypertrophy. About 0.6 g per pound a day is a good place to be.",
                ],
                sources: [
                    Source(
                        title: "Morton 2018: protein and muscle gains",
                        url: URL(string: "https://doi.org/10.1136/bjsports-2017-097608")!
                    ),
                ]
            ),
            Entry(
                question: "How important are supplements?",
                paragraphs: [
                    "They aren't. Get what you need from a rich diet.",
                ]
            ),
            Entry(
                question: "Well, creatine is good, right?",
                paragraphs: [
                    "Creatine monohydrate does help in the gym. With a daily dose, expect to gain maybe 5 to 10% more muscle mass over a given time.",
                ]
            ),
            Entry(
                question: "Then beta-alanine is super important.",
                paragraphs: [
                    "Not really. It has a big psychological effect because, for most people, it causes a slight tingling of the skin, which people take as a sign that \"it's working\". That's placebo.",
                    "At best, it might help a little with high-intensity efforts lasting about 30 seconds to 5 minutes. That isn't lifting weights.",
                ]
            ),
            Entry(
                question: "Then why do I lift so much better on pre-workout?",
                paragraphs: [
                    "Caffeine. There's a reason some lifting competitions restrict caffeine on the day of an event. Caffeine is basically the only supplement that will make you lift harder.",
                    "We'll let you decide whether you need it. Depending on when you train, caffeine can hurt your sleep, and remember: gains don't happen in the gym, they happen while you sleep.",
                ]
            ),
        ]),
    ]
}
