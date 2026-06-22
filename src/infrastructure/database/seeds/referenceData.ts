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
  timeBased: boolean;
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
  { name: "EZ Bar", weightOverloadable: true, repOverloadable: true, timeOverloadable: false },
  { name: "Trap Bar", weightOverloadable: true, repOverloadable: true, timeOverloadable: false },
];

const referenceExerciseCsv = `exercise-name,equipment,primary_muscle,secondary_muscle,reps_only,min_reps_hypertrophy,max_reps_hypertrophy,time_based
Barbell Bench Press,Barbell,Chest,Triceps;Shoulders,FALSE,5,12
Barbell Incline Bench Press,Barbell,Chest,Triceps;Shoulders,FALSE,6,12
Barbell Close Grip Bench Press,Barbell,Triceps,Chest;Shoulders,FALSE,6,12
Barbell Overhead Press,Barbell,Shoulders,Triceps;Core,FALSE,5,10
Barbell Push Press,Barbell,Shoulders,Triceps;Quads;Core,FALSE,4,8
Barbell Bent Over Row,Barbell,Back,Biceps;Forearms;Core,FALSE,6,12
Barbell Pendlay Row,Barbell,Back,Biceps;Forearms;Core,FALSE,5,10
Barbell T Bar Row,Barbell,Back,Biceps;Forearms,FALSE,6,12
Barbell Shrug,Barbell,Back,Forearms,FALSE,8,15
Barbell Back Squat,Barbell,Quads,Glutes;Hamstrings;Core,FALSE,6,12
Barbell Front Squat,Barbell,Quads,Glutes;Core,FALSE,6,12
Barbell Romanian Deadlift,Barbell,Hamstrings,Glutes;Back;Forearms,FALSE,6,12
Barbell Deadlift,Barbell,Glutes,Hamstrings;Quads;Back;Forearms;Core,FALSE,4,8
Barbell Sumo Deadlift,Barbell,Glutes,Hamstrings;Quads;Back;Forearms;Core,FALSE,4,8
Barbell Hip Thrust,Barbell,Glutes,Hamstrings;Core,FALSE,6,12
Barbell Good Morning,Barbell,Hamstrings,Glutes;Back;Core,FALSE,6,10
Barbell Bulgarian Split Squat,Barbell,Quads,Glutes;Hamstrings;Core,FALSE,8,15
Barbell Calf Raise,Barbell,Calves,Core,FALSE,8,20
Barbell Curl,Barbell,Biceps,Forearms,FALSE,8,15
Barbell Reverse Curl,Barbell,Forearms,Biceps,FALSE,10,20
Barbell Walking Lunge,Barbell,Quads,Glutes;Hamstrings,FALSE,8,15
Barbell Reverse Lunge,Barbell,Glutes,Quads;Hamstrings,FALSE,8,15
Barbell Lunge,Barbell,Quads,Glutes;Hamstrings,FALSE,8,15
Barbell Skull Crusher,Barbell,Triceps,Shoulders,FALSE,8,15
Dumbbell Bench Press,Dumbbell,Chest,Triceps;Shoulders,FALSE,6,12
Dumbbell Incline Bench Press,Dumbbell,Chest,Triceps;Shoulders,FALSE,6,12
Dumbbell Fly,Dumbbell,Chest,Shoulders,FALSE,10,20
Dumbbell Incline Fly,Dumbbell,Chest,Shoulders,FALSE,10,20
Dumbbell Shoulder Press,Dumbbell,Shoulders,Triceps;Core,FALSE,6,12
Dumbbell Arnold Press,Dumbbell,Shoulders,Triceps;Core,FALSE,8,15
Dumbbell Lateral Raise,Dumbbell,Shoulders,,FALSE,8,20
Dumbbell Rear Delt Fly,Dumbbell,Shoulders,Back,FALSE,10,25
Dumbbell Shrug,Dumbbell,Back,Forearms,FALSE,10,20
Dumbbell One Arm Row,Dumbbell,Back,Biceps;Forearms;Core,FALSE,8,15
Dumbbell Chest Supported Row,Dumbbell,Back,Biceps;Forearms,FALSE,8,15
Dumbbell Romanian Deadlift,Dumbbell,Hamstrings,Glutes;Back;Forearms,FALSE,8,15
Dumbbell Goblet Squat,Dumbbell,Quads,Glutes;Core,FALSE,8,15
Dumbbell Split Squat,Dumbbell,Quads,Glutes;Hamstrings;Core,FALSE,8,15
Dumbbell Bulgarian Split Squat,Dumbbell,Quads,Glutes;Hamstrings;Core,FALSE,8,15
Dumbbell Lunge,Dumbbell,Quads,Glutes;Hamstrings,FALSE,8,15
Dumbbell Reverse Lunge,Dumbbell,Glutes,Quads;Hamstrings,FALSE,8,15
Dumbbell Walking Lunge,Dumbbell,Quads,Glutes;Hamstrings;Core;Forearms,FALSE,10,20
Dumbbell Calf Raise,Dumbbell,Calves,Core;Forearms,FALSE,10,25
Dumbbell Curl,Dumbbell,Biceps,Forearms,FALSE,8,15
Dumbbell Hammer Curl,Dumbbell,Biceps,Forearms,FALSE,8,15
Dumbbell Incline Curl,Dumbbell,Biceps,Forearms,FALSE,10,20
Dumbbell Wrist Curl,Dumbbell,Forearms,,FALSE,8,20
Dumbbell Reverse Wrist Curl,Dumbbell,Forearms,,FALSE,8,20
Dumbbell Overhead Triceps Extension,Dumbbell,Triceps,Shoulders,FALSE,10,20
Dumbbell Skull Crusher,Dumbbell,Triceps,Shoulders,FALSE,8,15
Machine Chest Press,Machine,Chest,Triceps;Shoulders,FALSE,6,12
Machine Incline Chest Press,Machine,Chest,Triceps;Shoulders,FALSE,6,12
Machine Chest Fly,Machine,Chest,Shoulders,FALSE,10,20
Machine Shoulder Press,Machine,Shoulders,Triceps,FALSE,6,12
Machine Lateral Raise,Machine,Shoulders,,FALSE,10,25
Machine Rear Delt Fly,Machine,Shoulders,Back,FALSE,10,25
Machine Row,Machine,Back,Biceps;Forearms,FALSE,8,15
Machine Pulldown,Machine,Back,Biceps;Forearms,FALSE,8,15
Machine Assisted Pull Up,Machine,Back,Biceps;Forearms,FALSE,6,15
Machine Assisted Dip,Machine,Triceps,Chest;Shoulders,FALSE,6,15
Machine Preacher Curl,Machine,Biceps,Forearms,FALSE,8,15
Machine Triceps Extension,Machine,Triceps,,FALSE,8,15
Machine Hack Squat,Machine,Quads,Glutes;Hamstrings,FALSE,6,12
Machine Leg Extension,Machine,Quads,,FALSE,10,20
Machine Seated Leg Curl,Machine,Hamstrings,,FALSE,10,20
Machine Lying Leg Curl,Machine,Hamstrings,,FALSE,10,20
Machine Hip Thrust,Machine,Glutes,Hamstrings,FALSE,8,15
Machine Glute Kickback,Machine,Glutes,Hamstrings,FALSE,10,20
Machine Hip Abduction,Machine,Glutes,,FALSE,12,25
Machine Calf Raise,Machine,Calves,,FALSE,8,20
Machine Seated Calf Raise,Machine,Calves,,FALSE,10,25
Machine Back Extension,Machine,Back,Glutes;Hamstrings,FALSE,10,20
Cable Chest Fly,Cable,Chest,Shoulders,FALSE,10,20
Cable Low to High Fly,Cable,Chest,Shoulders,FALSE,10,20
Cable High to Low Fly,Cable,Chest,Shoulders,FALSE,10,20
Cable Lateral Raise,Cable,Shoulders,,FALSE,10,25
Cable Rear Delt Fly,Cable,Shoulders,Back,FALSE,10,25
Cable Face Pull,Cable,Shoulders,Back,FALSE,12,25
Cable Row,Cable,Back,Biceps;Forearms,FALSE,8,15
Cable Lat Pulldown,Cable,Back,Biceps;Forearms,FALSE,8,15
Cable Straight Arm Pulldown,Cable,Back,Triceps,FALSE,10,20
Cable Curl,Cable,Biceps,Forearms,FALSE,10,20
Cable Rope Hammer Curl,Cable,Biceps,Forearms,FALSE,10,20
Cable Reverse Curl,Cable,Forearms,Biceps,FALSE,10,20
Cable Triceps Pushdown,Cable,Triceps,,FALSE,10,20
Cable Overhead Triceps Extension,Cable,Triceps,Shoulders,FALSE,10,20
Cable Crunch,Cable,Core,,FALSE,10,25
Cable Glute Kickback,Cable,Glutes,Hamstrings,FALSE,12,25
Cable Pull Through,Cable,Glutes,Hamstrings;Back,FALSE,10,20
Pull Up,Bodyweight,Back,Biceps;Forearms;Core,TRUE,5,12
Chin Up,Bodyweight,Back,Biceps;Forearms;Core,TRUE,5,12
Neutral Grip Pull Up,Bodyweight,Back,Biceps;Forearms;Core,TRUE,5,12
Inverted Row,Bodyweight,Back,Biceps;Forearms;Core,TRUE,8,20
Dip,Bodyweight,Triceps,Chest;Shoulders,TRUE,6,15
Push Up,Bodyweight,Chest,Triceps;Shoulders;Core,TRUE,8,25
Close Grip Push Up,Bodyweight,Triceps,Chest;Shoulders;Core,TRUE,8,25
Pike Push Up,Bodyweight,Shoulders,Triceps;Core,TRUE,6,15
Bodyweight Bulgarian Split Squat,Bodyweight,Quads,Glutes;Hamstrings;Core,TRUE,10,20
Single Leg Calf Raise,Bodyweight,Calves,Core,TRUE,10,25
Hanging Knee Raise,Bodyweight,Core,Forearms,TRUE,8,20
Hanging Leg Raise,Bodyweight,Core,Forearms,TRUE,8,20
Plank,Bodyweight,Core,,TRUE,2,12,TRUE
Weighted Plank,Bodyweight,Core,,FALSE,2,12,TRUE
Side Plank,Bodyweight,Core,,TRUE,2,12,TRUE
Weighted Pull Up,Bodyweight,Back,Biceps;Forearms;Core,FALSE,4,10
Weighted Dip,Bodyweight,Triceps,Chest;Shoulders,FALSE,5,12
Leg Press,Leg Press,Quads,Glutes;Hamstrings,FALSE,8,15
Single Leg Leg Press,Leg Press,Quads,Glutes;Hamstrings,FALSE,10,20
Leg Press Calf Raise,Leg Press,Calves,,FALSE,10,25
Smith Machine Bench Press,Smith Machine,Chest,Triceps;Shoulders,FALSE,6,12
Smith Machine Incline Press,Smith Machine,Chest,Triceps;Shoulders,FALSE,6,12
Smith Machine Back Squat,Smith Machine,Quads,Glutes;Hamstrings;Core,FALSE,6,12
Smith Machine Front Squat,Smith Machine,Quads,Glutes;Hamstrings,FALSE,6,12
Smith Machine Hip Thrust,Smith Machine,Glutes,Hamstrings;Core,FALSE,8,15
EZ Bar Curl,EZ Bar,Biceps,Forearms,FALSE,8,15
EZ Bar Skull Crusher,EZ Bar,Triceps,Shoulders,FALSE,8,15
Trap Bar Deadlift,Trap Bar,Glutes,Hamstrings;Quads;Back;Forearms;Core,FALSE,4,8`;

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
        timeBased = "FALSE",
      ] = row.split(",");

      return {
        name,
        equipment,
        primaryMuscle,
        secondaryMuscles: secondaryMuscleList ? secondaryMuscleList.split(";").filter(Boolean) : [],
        repsOnly: repsOnly.toLowerCase() === "true",
        timeBased: timeBased.toLowerCase() === "true",
        minRepsHypertrophy: Number(minRepsHypertrophy),
        maxRepsHypertrophy: Number(maxRepsHypertrophy),
      };
    });
}
