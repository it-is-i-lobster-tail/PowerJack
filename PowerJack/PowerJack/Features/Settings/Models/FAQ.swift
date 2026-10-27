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
        let answer: [Part]
        var sources: [Source] = []
    }

    /// A paragraph of an answer, or one of its diagrams. Paragraphs can be written as plain strings.
    enum Part: Hashable, ExpressibleByStringLiteral {
        case text(String)
        case figure(Figure)

        init(stringLiteral text: String) {
            self = .text(text)
        }
    }

    /// The diagrams that explain how training progresses, drawn by `FAQFigure`.
    enum Figure: Hashable, CaseIterable {
        case weeklyLoop
        case block
        case programLengths
        case hypertrophy
        case strength
        case powerJack
        case pain
        case breaks
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
                question: "What is PowerJack?",
                answer: [
                    "A lifting app that plans your training and moves it forward for you.",
                    "You pick a program, lift, and tell PowerJack how each exercise felt. It uses that to set up next week, so your plan keeps pace with you instead of staying the same.",
                ]
            ),
            Entry(
                question: "Why was PowerJack made?",
                answer: [
                    "Most lifting apps are either a notebook or a fixed plan. A notebook records what you did and leaves the thinking to you. A fixed plan tells you what to do, but doesn't change when a week goes badly, or when you're ready for more.",
                    "PowerJack was made to sit in between, like a coach in your pocket. Your workout is ready when you open the app, it adjusts to how your training is really going, and it stays out of the way while you lift.",
                    "It's also private by design: no accounts, no ads and no tracking. And its code is public, so anyone can see exactly how it works.",
                ]
            ),
            Entry(
                question: "Where does the name come from?",
                answer: [
                    "Getting \"jacked\" means building bigger muscles. The scientific word for it is hypertrophy. Powerlifting is about getting as strong as you can, especially at the squat, bench press and deadlift.",
                    "Training for size and training for strength overlap, but each works best when it's planned for. Wanting both, bigger and stronger, is PowerJacking.",
                    "That's where the name comes from, and why there are three kinds of programs: Hypertrophy, Strength and PowerJack.",
                ]
            ),
            Entry(
                question: "Who is PowerJack for?",
                answer: [
                    "Adults who already know how to do their lifts with good form. PowerJack plans your training, but it doesn't teach technique. If you're brand new to lifting, learn the basics with a coach first.",
                    "Beyond that, it works whether this is your first real program or you've been lifting for years. Your plan starts from what you can do today.",
                ]
            ),
            Entry(
                question: "Is it based on research?",
                answer: [
                    "Yes. How PowerJack plans, from how close to your limit each set ends to how many sets each muscle gets, how long you rest and when you take a lighter week, follows published research on building muscle and strength.",
                    "You don't need to know any of it to use the app. These are some of the main studies behind it.",
                ],
                sources: [
                    Source(
                        title: "Schoenfeld 2017: weekly sets and muscle growth",
                        url: URL(string: "https://doi.org/10.1080/02640414.2016.1210197")!
                    ),
                    Source(
                        title: "Schoenfeld 2017: light vs heavy weights",
                        url: URL(string: "https://doi.org/10.1519/JSC.0000000000002200")!
                    ),
                    Source(
                        title: "Schoenfeld 2021: reps for size and strength",
                        url: URL(string: "https://doi.org/10.3390/sports9020032")!
                    ),
                    Source(
                        title: "Currier 2023: training for strength",
                        url: URL(string: "https://doi.org/10.1136/bjsports-2023-106807")!
                    ),
                    Source(
                        title: "Robinson 2024: how close to failure",
                        url: URL(string: "https://doi.org/10.1007/s40279-024-02069-2")!
                    ),
                    Source(
                        title: "Pelland 2026: weekly sets and training days",
                        url: URL(string: "https://doi.org/10.1007/s40279-025-02344-w")!
                    ),
                    Source(
                        title: "Schoenfeld 2016: longer rests between sets",
                        url: URL(string: "https://doi.org/10.1519/JSC.0000000000001272")!
                    ),
                    Source(
                        title: "Spiering 2021: what it takes to keep muscle",
                        url: URL(string: "https://doi.org/10.1519/JSC.0000000000003964")!
                    ),
                    Source(
                        title: "Enes 2024: when more sets stop helping",
                        url: URL(string: "https://doi.org/10.1249/MSS.0000000000003317")!
                    ),
                ]
            ),
            Entry(
                question: "Is my training private?",
                answer: [
                    "Yes. There's no account to make, and no ads, analytics or tracking. Everything you log stays on your iPhone.",
                    "If you turn on iCloud Backup in Settings, a copy is kept in your own private iCloud, so a new iPhone or a reinstall picks up where you left off. Only you can see it, and turning it off deletes that copy.",
                ]
            ),
        ]),
        Topic(title: "Using PowerJack", entries: [
            Entry(
                question: "How do I get started?",
                answer: [
                    "1. Open Templates and choose a kind of program at the top: Hypertrophy, Strength or PowerJack.",
                    "2. Pick a template. Each one shows how many days a week it trains. Tap it to see its workouts, and change anything you like.",
                    "3. Open Programs, tap +, choose your template and how many weeks to run it, then tap Start Program.",
                    "4. Tap Start Workout. Your first week sets your starting point.",
                    "Choose a template with the number of days you can train every week, not the most you could manage in a good week.",
                ]
            ),
            Entry(
                question: "Which kind of program should I choose?",
                answer: [
                    "Hypertrophy, if building muscle is your main goal. Most sets use moderate weights for more reps, taken close to your limit.",
                    "Strength, if you want to lift as much as you can on big lifts like the squat, bench press and deadlift. Those lifts stay heavy, for fewer reps.",
                    "PowerJack, if you want both. Your main lifts start with one heavy set, then lighter sets for more reps, and the rest of the workout builds muscle.",
                    "Each one builds some muscle and some strength. You can choose a different kind for your next program.",
                ]
            ),
            Entry(
                question: "What's the difference between a template and a program?",
                answer: [
                    "A template is your training week on paper: which days you train, and which exercises you do on each.",
                    "A program is a template in action, for the number of weeks you choose. It keeps track of what you lift and plans each week from the one before.",
                    "Editing a template doesn't change programs you've already started from it. You run one program at a time, so starting a new one stops the current one.",
                ]
            ),
            Entry(
                question: "Can I build my own template?",
                answer: [
                    "Yes. In Templates, tap + and give it a name, how many days a week you'll train, and up to four focus muscles: the ones you most want to grow. Hypertrophy and PowerJack programs give focus muscles extra sets.",
                    "Then build each day by adding exercises. Swipe right on an exercise to superset it with the one below, so you do one set of each in turn and then rest. Swipe left to edit or remove it. You can also copy a whole day to another day.",
                    "Everything saves as you go.",
                ]
            ),
            Entry(
                question: "What happens during a workout?",
                answer: [
                    "Every set is filled in with its target weight and reps, and each exercise shows its aim: how many reps to leave in the tank.",
                    "Warm-up sets come first and don't count toward your progress. For each working set, tap the circle when you're done. If you lifted a different weight or did different reps, change the numbers first, so next week is planned from what really happened.",
                    "A rest timer counts down between sets. It can show in the Dynamic Island and on your Lock Screen too.",
                    "After an exercise's last set, rate it: how many more good reps you could have done, and whether anything hurt. It takes a few seconds, and it's what your next week is planned from.",
                    "After the last exercise, you'll see the whole workout. Tap any exercise to go back to it, or tap Finish Workout to see your summary.",
                ]
            ),
            Entry(
                question: "What if I can't do an exercise today?",
                answer: [
                    "Use the ••• menu. Change Exercise swaps it for another one for the rest of the program, with weights set for the new exercise. Your template stays as it was.",
                    "Skip Exercise skips what's left of it today, and Skip Workout skips the whole day. Skipped work isn't made up later. Your plan simply carries on.",
                ]
            ),
            Entry(
                question: "How do rest times work?",
                answer: [
                    "Each exercise has a fatigue level. More tiring exercises, like squats, get longer rests. Set how long each rest is in Settings > Rest Between Sets, or give one exercise its own rest time by editing it.",
                    "Strength and PowerJack programs give your heaviest lifts longer rests of their own.",
                ]
            ),
            Entry(
                question: "What does the Volume tab show?",
                answer: [
                    "How many hard sets each muscle has averaged per week, over the last 30 days, 90 days, year, or all time.",
                    "The colors show what that amount does: 0–2 sets a week is too little, 3–5 maintains a muscle, 6–12 grows it, 13–25 is where growth tops out, and 26 or more is likely more than you can recover from.",
                ]
            ),
            Entry(
                question: "Does it work on Apple Watch?",
                answer: [
                    "Yes. With iCloud Backup turned on, you can start or resume a workout, log sets, rate exercises and finish from your watch. Start the program itself on your iPhone.",
                ]
            ),
            Entry(
                question: "What can I change in Settings?",
                answer: [
                    "The rest timer, how long you rest, lb or kg, light or dark appearance, hints and iCloud Backup.",
                    "Load Steps sets the smallest weight jump for each kind of equipment. Strength programs round your weights to it, so set it to match the plates and dumbbells you have.",
                ]
            ),
        ]),
        Topic(title: "How Progress Works", entries: [
            Entry(
                question: "How does PowerJack plan my next week?",
                answer: [
                    "Every week runs the same loop. You lift and rate each exercise. When the week is done, PowerJack looks at each exercise in turn and decides what comes next.",
                    .figure(.weeklyLoop),
                    "Each kind of program takes its steps a little differently. The answers below show how.",
                ]
            ),
            Entry(
                question: "What does \"reps left\" mean?",
                answer: [
                    "How many more good reps you could have done when you stopped the set. If you could have managed 10 but stopped at 8, you had 2 reps left.",
                    "\"Good\" is the key word. Once your form breaks down, the set is over, even if you could have forced out more.",
                    "Each exercise has an aim, like 2 reps left. Being honest about how close you got keeps your weights right. Rate sets easier than they were and the jumps get too big. Rate them harder and your progress stalls.",
                ]
            ),
            Entry(
                question: "Why do some weeks feel harder than others?",
                answer: [
                    "Your weeks are grouped into blocks. Each block has a few hard weeks that ask a little more of you each time, then a lighter week to recover. Here's a block from a 10-week program:",
                    .figure(.block),
                    "The lighter week has about half the sets, at about 90% of the weight, with at least 3 reps left on every set. It's when your body catches up on the work, so it's worth doing.",
                    "If training feels harder than planned two weeks running, the lighter week can come early. The next block starts a little easier again, from the weights you finished on.",
                ]
            ),
            Entry(
                question: "How long is a block?",
                answer: [
                    "It depends on how long your program is. PowerJack fits the blocks to it, so every program of 4 weeks or more ends on a lighter week.",
                    .figure(.programLengths),
                ]
            ),
            Entry(
                question: "Where do my starting weights come from?",
                answer: [
                    "If you've done an exercise in PowerJack in the last few months, even in another program, it starts from those sets.",
                    "If the exercise is new to you, week 1 finds your level. Pick a weight you think leaves about as many reps in the tank as the exercise's aim, and log what you actually did. Your weights for week 2 come from there.",
                    "In Hypertrophy and PowerJack programs, week 1 has fewer sets on purpose, and they build up over the weeks that follow. Strength programs use the first two weeks to dial in your main lifts.",
                ]
            ),
            Entry(
                question: "How do Hypertrophy programs progress?",
                answer: [
                    "Reps first, then weight. Each exercise has a rep range, like 8–12. You add reps week to week until you reach the top of the range. Then the weight goes up, and your reps start lower in the range again.",
                    .figure(.hypertrophy),
                    "When the next weight up would be a big jump, like moving up a dumbbell, the range stretches so you can add more reps first.",
                    "Sets grow as well. Each muscle works up to about 10 hard sets a week. At the end of each block, a muscle that's progressing and recovering well can get more sets, up to about 20 a week, or 25 for focus muscles. One that's struggling gets fewer.",
                ]
            ),
            Entry(
                question: "How do Strength programs progress?",
                answer: [
                    "More weight, same reps. Your main lifts, up to four, like the squat, bench press, deadlift and the first big lift of each day, stay heavy at around 4 to 6 reps. The weight is what changes week to week.",
                    .figure(.strength),
                    "Weights round to your Load Steps in Settings. When the next step is a big jump for that weight, you add a rep or two first, then take the jump.",
                    "Your other exercises add reps first, then weight, like in Hypertrophy programs.",
                    "If one lift keeps feeling harder than planned, it gets a short lighter week of its own. If a lift stalls for a couple of months, PowerJack changes things up to get it moving again.",
                ]
            ),
            Entry(
                question: "How do PowerJack programs progress?",
                answer: [
                    "Heavy top set, then volume. Your main lifts are trained for strength, and everything else builds muscle.",
                    .figure(.powerJack),
                    "Focus muscles start with a couple of extra sets and have more room to grow.",
                ]
            ),
            Entry(
                question: "What happens if something hurts?",
                answer: [
                    "Hard work burns, and fades soon after the set. Pain is different: sharp, in a joint, or still there after you rest. Rate it honestly, and PowerJack backs off until it settles.",
                    .figure(.pain),
                    "Once the pain settles, your weights build back up over the next few sessions.",
                    "PowerJack only changes your training. If pain is severe or doesn't go away, stop and see a health professional.",
                ]
            ),
            Entry(
                question: "What if I miss workouts or take a break?",
                answer: [
                    "Life happens. Skipped workouts aren't made up, and your plan carries on from where you are. After a longer break, PowerJack eases you back in.",
                    .figure(.breaks),
                ]
            ),
        ]),
        Topic(title: "Getting the Most Out of It", entries: [
            Entry(
                question: "How often should I train?",
                answer: [
                    "As often as you can keep up for the long run. Three workouts a week for years will take you much further than five a week now and then.",
                    "Choose a template with the number of days you can always make. You can move up to more days in a later program.",
                ]
            ),
            Entry(
                question: "How hard should I push?",
                answer: [
                    "Close to your limit, but never past good form. Aim for the reps left shown on each exercise. That's hard enough to build muscle and strength, and easy enough to recover from by next week.",
                    "Every rep should look like the first. Swinging, bouncing or cutting a rep short moves the work away from the muscle you're training and raises your odds of getting hurt.",
                ]
            ),
            Entry(
                question: "How do I get my ratings right?",
                answer: [
                    "Rate right after the last set, while you still remember how it felt, and rate the set you did, not the one you hoped for.",
                    "Count only good reps. If your form would have slipped on the next rep, that's 0 reps left.",
                    "Log the weight and reps you really did. Your next week is built from them, so honest numbers give you the right next step.",
                ]
            ),
            Entry(
                question: "Should I skip the lighter weeks?",
                answer: [
                    "No. They're meant to feel easy. Tiredness builds up quietly over the hard weeks, and the lighter week lets it wear off, so you start the next block fresher and ready to lift more.",
                ]
            ),
            Entry(
                question: "Can I change the plan?",
                answer: [
                    "Make it yours where it counts: swap exercises that don't feel right, pick your focus muscles, and set rest times that suit you.",
                    "Then let PowerJack set the weights and reps. They come from your own ratings, so following them is how your plan keeps fitting you.",
                ]
            ),
            Entry(
                question: "What about food and sleep?",
                answer: [
                    "Muscle grows and strength builds while you recover, not while you lift. Sleep well, and eat enough protein. For most people, the benefit levels off around 0.7 g per pound of body weight a day (1.6 g per kg).",
                ],
                sources: [
                    Source(
                        title: "Morton 2018: protein and muscle gains",
                        url: URL(string: "https://doi.org/10.1136/bjsports-2017-097608")!
                    ),
                ]
            ),
        ]),
    ]
}
