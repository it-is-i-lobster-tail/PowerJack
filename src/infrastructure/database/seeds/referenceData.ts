export interface ReferenceEquipmentSeed {
  name: string;
  weightOverloadable: boolean;
  repOverloadable: boolean;
  timeOverloadable: boolean;
}

export interface ReferenceExerciseSeed {
  name: string;
  primaryMuscle: string;
  secondaryMuscles: string[];
  equipment: string;
  repsOnly: boolean;
  minRepsHypertrophy: number;
  maxRepsHypertrophy: number;
}

export const referenceMuscles = [
  "Back",
  "Biceps",
  "Calves",
  "Chest",
  "Core",
  "Forearms",
  "Glutes",
  "Hamstrings",
  "Quads",
  "Shoulders",
  "Triceps",
] as const;

export const referenceEquipment: ReferenceEquipmentSeed[] = [
  { name: "Barbell", weightOverloadable: true, repOverloadable: true, timeOverloadable: false },
  { name: "Bodyweight", weightOverloadable: false, repOverloadable: true, timeOverloadable: true },
  { name: "Cable", weightOverloadable: true, repOverloadable: true, timeOverloadable: false },
  { name: "Dumbbell", weightOverloadable: true, repOverloadable: true, timeOverloadable: false },
  { name: "Leg Press", weightOverloadable: true, repOverloadable: true, timeOverloadable: false },
  { name: "Machine", weightOverloadable: true, repOverloadable: true, timeOverloadable: false },
  { name: "Smith Machine", weightOverloadable: true, repOverloadable: true, timeOverloadable: false },
  { name: "Landmine", weightOverloadable: true, repOverloadable: true, timeOverloadable: false },
  { name: "EZ Bar", weightOverloadable: true, repOverloadable: true, timeOverloadable: false },
  { name: "Trap Bar", weightOverloadable: true, repOverloadable: true, timeOverloadable: false },
  { name: "Sled", weightOverloadable: true, repOverloadable: true, timeOverloadable: false },
  { name: "Kettlebell", weightOverloadable: true, repOverloadable: true, timeOverloadable: false },
];

const referenceExerciseCsv = `exercise-name,equipment,primary_muscle,secondary_muscle,reps_only,min_reps_hypertrophy,max_reps_hypertrophy
Barbell Bench Press,Barbell,Chest,Triceps;Shoulders,false,5,12
Barbell Incline Bench Press,Barbell,Chest,Triceps;Shoulders,false,6,12
Barbell Decline Bench Press,Barbell,Chest,Triceps;Shoulders,false,6,12
Barbell Close-Grip Bench Press,Barbell,Triceps,Chest;Shoulders,false,6,12
Barbell Floor Press,Barbell,Chest,Triceps;Shoulders,false,5,10
Barbell Overhead Press,Barbell,Shoulders,Triceps;Core,false,5,10
Barbell Push Press,Barbell,Shoulders,Triceps;Quads;Core,false,4,8
Barbell Upright Row,Barbell,Shoulders,Back;Biceps;Forearms,false,8,15
Barbell Front Raise,Barbell,Shoulders,Chest,false,8,15
Barbell Bent-Over Row,Barbell,Back,Biceps;Forearms;Core,false,6,12
Barbell Pendlay Row,Barbell,Back,Biceps;Forearms;Core,false,5,10
Barbell T-Bar Row,Barbell,Back,Biceps;Forearms,false,6,12
Barbell Shrug,Barbell,Back,Forearms,false,8,15
Barbell Back Squat,Barbell,Quads,Glutes;Hamstrings;Core,false,6,12
Barbell Front Squat,Barbell,Quads,Glutes;Core,false,6,12
Barbell Box Squat,Barbell,Quads,Glutes;Hamstrings;Core,false,5,10
Barbell Pause Squat,Barbell,Quads,Glutes;Hamstrings;Core,false,5,10
Barbell Romanian Deadlift,Barbell,Hamstrings,Glutes;Back;Forearms,false,6,12
Barbell Conventional Deadlift,Barbell,Back,Glutes;Hamstrings;Quads;Forearms;Core,false,4,8
Barbell Sumo Deadlift,Barbell,Glutes,Hamstrings;Quads;Back;Forearms;Core,false,4,8
Barbell Hip Thrust,Barbell,Glutes,Hamstrings;Core,false,6,12
Barbell Glute Bridge,Barbell,Glutes,Hamstrings;Core,false,8,15
Barbell Good Morning,Barbell,Hamstrings,Glutes;Back;Core,false,6,10
Barbell Lunge,Barbell,Quads,Glutes;Hamstrings;Core,false,8,15
Barbell Reverse Lunge,Barbell,Quads,Glutes;Hamstrings;Core,false,8,15
Barbell Bulgarian Split Squat,Barbell,Quads,Glutes;Hamstrings;Core,false,8,15
Barbell Calf Raise,Barbell,Calves,Core,false,8,20
Barbell Curl,Barbell,Biceps,Forearms,false,8,15
Barbell Drag Curl,Barbell,Biceps,Forearms,false,8,15
Barbell Reverse Curl,Barbell,Forearms,Biceps,false,10,20
Barbell Skull Crusher,Barbell,Triceps,Shoulders,false,8,15
Barbell JM Press,Barbell,Triceps,Chest;Shoulders,false,6,12
Barbell Wrist Curl,Barbell,Forearms,,false,12,25
Barbell Reverse Wrist Curl,Barbell,Forearms,,false,12,25
Dumbbell Bench Press,Dumbbell,Chest,Triceps;Shoulders,false,6,12
Dumbbell Incline Bench Press,Dumbbell,Chest,Triceps;Shoulders,false,6,12
Dumbbell Decline Bench Press,Dumbbell,Chest,Triceps;Shoulders,false,8,15
Dumbbell Floor Press,Dumbbell,Chest,Triceps;Shoulders,false,6,12
Dumbbell Fly,Dumbbell,Chest,Shoulders,false,10,20
Dumbbell Incline Fly,Dumbbell,Chest,Shoulders,false,10,20
Dumbbell Pullover,Dumbbell,Back,Chest;Triceps,false,10,20
Dumbbell Shoulder Press,Dumbbell,Shoulders,Triceps;Core,false,6,12
Dumbbell Arnold Press,Dumbbell,Shoulders,Triceps;Core,false,8,15
Dumbbell Lateral Raise,Dumbbell,Shoulders,,false,8,20
Dumbbell Front Raise,Dumbbell,Shoulders,Chest,false,8,20
Dumbbell Rear Delt Fly,Dumbbell,Shoulders,Back,false,10,25
Dumbbell Upright Row,Dumbbell,Shoulders,Biceps;Forearms,false,8,15
Dumbbell Shrug,Dumbbell,Back,Forearms,false,10,20
Dumbbell One-Arm Row,Dumbbell,Back,Biceps;Forearms;Core,false,8,15
Dumbbell Chest-Supported Row,Dumbbell,Back,Biceps;Forearms,false,8,15
Dumbbell Seal Row,Dumbbell,Back,Biceps;Forearms,false,8,15
Dumbbell Romanian Deadlift,Dumbbell,Hamstrings,Glutes;Back;Forearms,false,8,15
Dumbbell Stiff-Leg Deadlift,Dumbbell,Hamstrings,Glutes;Back;Forearms,false,8,15
Dumbbell Goblet Squat,Dumbbell,Quads,Glutes;Core,false,8,15
Dumbbell Split Squat,Dumbbell,Quads,Glutes;Hamstrings;Core,false,8,15
Dumbbell Bulgarian Split Squat,Dumbbell,Quads,Glutes;Hamstrings;Core,false,8,15
Dumbbell Walking Lunge,Dumbbell,Quads,Glutes;Hamstrings;Core,false,10,20
Dumbbell Step-Up,Dumbbell,Quads,Glutes;Hamstrings;Core,false,8,15
Dumbbell Hip Thrust,Dumbbell,Glutes,Hamstrings;Core,false,8,15
Dumbbell Calf Raise,Dumbbell,Calves,Core;Forearms,false,10,25
Dumbbell Hammer Curl,Dumbbell,Biceps,Forearms,false,8,15
Dumbbell Incline Curl,Dumbbell,Biceps,Forearms,false,10,20
Dumbbell Concentration Curl,Dumbbell,Biceps,Forearms,false,10,20
Dumbbell Preacher Curl,Dumbbell,Biceps,Forearms,false,8,15
Dumbbell Zottman Curl,Dumbbell,Biceps,Forearms,false,10,20
Dumbbell Overhead Triceps Extension,Dumbbell,Triceps,Shoulders,false,10,20
Dumbbell Triceps Kickback,Dumbbell,Triceps,Shoulders,false,12,25
Dumbbell Skull Crusher,Dumbbell,Triceps,Shoulders,false,8,15
Dumbbell Wrist Curl,Dumbbell,Forearms,,false,12,25
Dumbbell Reverse Wrist Curl,Dumbbell,Forearms,,false,12,25
Machine Chest Press,Machine,Chest,Triceps;Shoulders,false,6,12
Machine Incline Chest Press,Machine,Chest,Triceps;Shoulders,false,6,12
Machine Shoulder Press,Machine,Shoulders,Triceps,false,6,12
Machine Lateral Raise,Machine,Shoulders,,false,10,25
Machine Rear Delt Fly,Machine,Shoulders,Back,false,10,25
Machine Row,Machine,Back,Biceps;Forearms,false,8,15
Machine High Row,Machine,Back,Biceps;Forearms,false,8,15
Machine Pulldown,Machine,Back,Biceps;Forearms,false,8,15
Machine Assisted Pull-Up,Machine,Back,Biceps;Forearms,false,6,15
Machine Assisted Dip,Machine,Triceps,Chest;Shoulders,false,6,15
Machine Preacher Curl,Machine,Biceps,Forearms,false,8,15
Machine Triceps Extension,Machine,Triceps,,false,8,15
Machine Hack Squat,Machine,Quads,Glutes;Hamstrings,false,6,12
Machine Leg Extension,Machine,Quads,,false,10,20
Machine Seated Leg Curl,Machine,Hamstrings,Calves,false,10,20
Machine Lying Leg Curl,Machine,Hamstrings,Calves,false,10,20
Machine Standing Leg Curl,Machine,Hamstrings,Calves,false,10,20
Machine Hip Thrust,Machine,Glutes,Hamstrings,false,8,15
Machine Glute Kickback,Machine,Glutes,Hamstrings,false,10,20
Machine Hip Abduction,Machine,Glutes,,false,12,25
Machine Hip Adduction,Machine,Glutes,Quads,false,12,25
Machine Calf Raise,Machine,Calves,,false,8,20
Machine Seated Calf Raise,Machine,Calves,,false,10,25
Machine Crunch,Machine,Core,,false,10,25
Machine Back Extension,Machine,Back,Glutes;Hamstrings,false,10,20
Cable Chest Fly,Cable,Chest,Shoulders,false,10,20
Cable Low-to-High Fly,Cable,Chest,Shoulders,false,10,20
Cable High-to-Low Fly,Cable,Chest,Shoulders,false,10,20
Cable Press,Cable,Chest,Triceps;Shoulders,false,8,15
Cable Crossover,Cable,Chest,Shoulders,false,10,20
Cable Lateral Raise,Cable,Shoulders,,false,10,25
Cable Front Raise,Cable,Shoulders,Chest,false,10,20
Cable Rear Delt Fly,Cable,Shoulders,Back,false,10,25
Cable Face Pull,Cable,Shoulders,Back,false,12,25
Cable Upright Row,Cable,Shoulders,Biceps;Forearms,false,10,20
Cable Row,Cable,Back,Biceps;Forearms,false,8,15
Cable Lat Pulldown,Cable,Back,Biceps;Forearms,false,8,15
Cable Straight-Arm Pulldown,Cable,Back,Triceps,false,10,20
Cable One-Arm Pulldown,Cable,Back,Biceps;Forearms,false,10,20
Cable Pullover,Cable,Back,Chest;Triceps,false,10,20
Cable Curl,Cable,Biceps,Forearms,false,10,20
Cable Rope Hammer Curl,Cable,Biceps,Forearms,false,10,20
Cable Preacher Curl,Cable,Biceps,Forearms,false,10,20
Cable Reverse Curl,Cable,Forearms,Biceps,false,10,20
Cable Triceps Pushdown,Cable,Triceps,,false,10,20
Cable Rope Pushdown,Cable,Triceps,,false,10,20
Cable Overhead Triceps Extension,Cable,Triceps,Shoulders,false,10,20
Cable Kickback,Cable,Triceps,Shoulders,false,12,25
Cable Crunch,Cable,Core,,false,10,25
Cable Woodchop,Cable,Core,Shoulders,false,10,20
Cable Glute Kickback,Cable,Glutes,Hamstrings,false,12,25
Cable Pull-Through,Cable,Glutes,Hamstrings;Back,false,10,20
Cable Hip Abduction,Cable,Glutes,,false,12,25
Cable Hip Adduction,Cable,Glutes,Quads,false,12,25
Pull-Up,Bodyweight,Back,Biceps;Forearms;Core,true,5,12
Chin-Up,Bodyweight,Back,Biceps;Forearms;Core,true,5,12
Neutral-Grip Pull-Up,Bodyweight,Back,Biceps;Forearms;Core,true,5,12
Wide-Grip Pull-Up,Bodyweight,Back,Biceps;Forearms;Core,true,5,12
Inverted Row,Bodyweight,Back,Biceps;Forearms;Core,true,8,20
Dip,Bodyweight,Triceps,Chest;Shoulders,true,6,15
Push-Up,Bodyweight,Chest,Triceps;Shoulders;Core,true,8,25
Close-Grip Push-Up,Bodyweight,Triceps,Chest;Shoulders;Core,true,8,25
Decline Push-Up,Bodyweight,Chest,Triceps;Shoulders;Core,true,8,25
Pike Push-Up,Bodyweight,Shoulders,Triceps;Core,true,6,15
Bodyweight Squat,Bodyweight,Quads,Glutes;Hamstrings;Core,true,12,30
Bodyweight Split Squat,Bodyweight,Quads,Glutes;Hamstrings;Core,true,10,25
Bodyweight Bulgarian Split Squat,Bodyweight,Quads,Glutes;Hamstrings;Core,true,10,20
Bodyweight Walking Lunge,Bodyweight,Quads,Glutes;Hamstrings;Core,true,12,30
Bodyweight Step-Up,Bodyweight,Quads,Glutes;Hamstrings;Core,true,10,25
Single-Leg Calf Raise,Bodyweight,Calves,Core,true,10,25
Hanging Knee Raise,Bodyweight,Core,Forearms,true,8,20
Hanging Leg Raise,Bodyweight,Core,Forearms,true,8,20
Reverse Crunch,Bodyweight,Core,,true,12,30
Crunch,Bodyweight,Core,,true,15,30
Leg Press,Leg Press,Quads,Glutes;Hamstrings,false,8,15
Single-Leg Leg Press,Leg Press,Quads,Glutes;Hamstrings,false,10,20
High-Foot Leg Press,Leg Press,Glutes,Hamstrings;Quads,false,10,20
Low-Foot Leg Press,Leg Press,Quads,Glutes,false,8,15
Wide-Stance Leg Press,Leg Press,Glutes,Quads;Hamstrings,false,10,20
Narrow-Stance Leg Press,Leg Press,Quads,Glutes,false,8,15
Paused Leg Press,Leg Press,Quads,Glutes;Hamstrings,false,8,15
Leg Press Calf Raise,Leg Press,Calves,,false,10,25
Single-Leg Leg Press Calf Raise,Leg Press,Calves,,false,10,25
Barbell Hack Squat,Barbell,Quads,Glutes;Hamstrings,false,6,12
Barbell Zercher Squat,Barbell,Quads,Glutes;Core;Back,false,5,10
Barbell Jefferson Squat,Barbell,Quads,Glutes;Hamstrings;Core,false,6,12
Barbell Sumo Romanian Deadlift,Barbell,Hamstrings,Glutes;Back;Forearms,false,6,12
Barbell Rack Pull,Barbell,Back,Glutes;Hamstrings;Forearms,false,4,8
Barbell Behind-the-Neck Press,Barbell,Shoulders,Triceps,false,6,12
Dumbbell Sumo Squat,Dumbbell,Quads,Glutes;Hamstrings;Core,false,8,15
Dumbbell Reverse Fly,Dumbbell,Shoulders,Back,false,10,25
Dumbbell Y-Raise,Dumbbell,Shoulders,Back,false,10,25
Dumbbell Spider Curl,Dumbbell,Biceps,Forearms,false,10,20
Dumbbell Tate Press,Dumbbell,Triceps,Chest,false,8,15
Machine Pec Deck,Machine,Chest,Shoulders,false,10,20
Machine Chest Fly,Machine,Chest,Shoulders,false,10,20
Machine Pullover,Machine,Back,Chest;Triceps,false,10,20
Cable Bayesian Curl,Cable,Biceps,Forearms,false,10,20
Cable Y-Raise,Cable,Shoulders,Back,false,10,25
Cable Single-Arm Triceps Pushdown,Cable,Triceps,,false,10,20
Weighted Pull-Up,Bodyweight,Back,Biceps;Forearms;Core,false,4,10
Weighted Chin-Up,Bodyweight,Back,Biceps;Forearms;Core,false,4,10
Weighted Dip,Bodyweight,Triceps,Chest;Shoulders,false,5,12
Smith Machine Bench Press,Smith Machine,Chest,Triceps;Shoulders,false,6,12
Smith Machine Incline Press,Smith Machine,Chest,Triceps;Shoulders,false,6,12
Landmine Row,Landmine,Back,Biceps;Forearms;Core,false,6,12
Bodyweight Back Extension,Bodyweight,Back,Glutes;Hamstrings,true,10,20
Reverse Hyperextension,Machine,Glutes,Hamstrings;Back,false,10,20
Cable External Rotation,Cable,Shoulders,,false,12,25
Cable Internal Rotation,Cable,Shoulders,,false,12,25
Dumbbell Cuban Press,Dumbbell,Shoulders,Triceps;Back,false,8,15
EZ Bar Curl,EZ Bar,Biceps,Forearms,false,8,15
Dumbbell Curl,Dumbbell,Biceps,Forearms,false,8,15
EZ Bar Skull Crusher,EZ Bar,Triceps,Shoulders,false,8,15
Machine Dip,Machine,Triceps,Chest;Shoulders,false,6,15
Smith Machine Back Squat,Smith Machine,Quads,Glutes;Hamstrings;Core,false,6,12
Smith Machine Split Squat,Smith Machine,Quads,Glutes;Hamstrings;Core,false,8,15
Dumbbell Lunge,Dumbbell,Quads,Glutes;Hamstrings;Core,false,8,15
Smith Machine Hip Thrust,Smith Machine,Glutes,Hamstrings;Core,false,8,15
Trap Bar Deadlift,Trap Bar,Quads,Glutes;Hamstrings;Back;Forearms;Core,false,4,8
Landmine Romanian Deadlift,Landmine,Hamstrings,Glutes;Back;Forearms,false,8,15
Nordic Hamstring Curl,Bodyweight,Hamstrings,Glutes;Calves,true,6,12
Machine Tibialis Raise,Machine,Calves,,false,12,25
Sled Push,Sled,Quads,Glutes;Hamstrings;Calves,false,10,20
Sled Drag,Sled,Quads,Glutes;Hamstrings;Calves,false,10,20
Kettlebell Swing,Kettlebell,Glutes,Hamstrings;Back;Core,false,10,20
Kettlebell Goblet Squat,Kettlebell,Quads,Glutes;Core,false,8,15
Landmine Squat,Landmine,Quads,Glutes;Core,false,8,15
Dumbbell Side Bend,Dumbbell,Core,Forearms,false,10,20
Scapular Push-Up,Bodyweight,Chest,Shoulders;Core,true,10,20
Cable Serratus Punch,Cable,Chest,Shoulders;Core,false,10,20
Incline Push-Up,Bodyweight,Chest,Triceps;Shoulders;Core,true,12,30
Deficit Push-Up,Bodyweight,Chest,Triceps;Shoulders;Core,true,8,25
Modified Candlestick,Bodyweight,Core,Quads;Glutes,true,6,15
Negative Pull-Up,Bodyweight,Back,Biceps;Forearms;Core,true,3,8
Archer Push-Up,Bodyweight,Chest,Triceps;Shoulders;Core,true,6,15
Weighted Push-Up,Bodyweight,Chest,Triceps;Shoulders;Core,false,6,12
Weighted Inverted Row,Bodyweight,Back,Biceps;Forearms;Core,false,6,12`;

export const referenceExercises: ReferenceExerciseSeed[] = parseReferenceExerciseCsv(referenceExerciseCsv);

function parseReferenceExerciseCsv(csv: string): ReferenceExerciseSeed[] {
  return csv
    .trim()
    .split("\n")
    .slice(1)
    .map((row) => {
      const [
        name,
        equipment,
        primaryMuscle,
        secondaryMuscleList,
        repsOnly,
        minRepsHypertrophy,
        maxRepsHypertrophy,
      ] = row.split(",");

      return {
        name,
        equipment,
        primaryMuscle,
        secondaryMuscles: secondaryMuscleList ? secondaryMuscleList.split(";").filter(Boolean) : [],
        repsOnly: repsOnly === "true",
        minRepsHypertrophy: Number(minRepsHypertrophy),
        maxRepsHypertrophy: Number(maxRepsHypertrophy),
      };
    });
}
