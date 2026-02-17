-- Animals seed data
-- 49 animals across 7 types

-- MAMMALS (12)
INSERT INTO animals (type, name, image_url, narration_text, lesson_order) VALUES
('mammal', 'Bear', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/mammals/bear.png',
'This is a bear! Bears are mammals. They are big, furry animals that live in forests and mountains. Some bears sleep all winter long in a cozy den - this is called hibernation. Bears love to eat berries, fish, and honey. Despite their size, bears can run very fast!', 1),

('mammal', 'Cat', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/mammals/cat.png',
'This is a cat! Cats are mammals. They are furry pets that love to purr, play, and take naps in sunny spots. They have soft paws with sharp claws that they can hide when they want to be gentle. Cats are great hunters and can see very well in the dark. They say "meow!"', 2),

('mammal', 'Dolphin', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/mammals/dolphin.png',
'This is a dolphin! Dolphins are mammals. They live in the ocean, but they are not fish! They breathe air and are very playful and smart. Dolphins talk to each other using clicks and whistles. They love to jump out of the water and swim with their friends.', 3),

('mammal', 'Elephant', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/mammals/elephant.png',
'This is an elephant! Elephants are mammals. They are the largest animals that live on land. They have long trunks that they use to grab food, drink water, and even say hello to their friends. Elephants are very smart and have amazing memories.', 4),

('mammal', 'Fox', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/mammals/fox.png',
'This is a fox! Foxes are mammals. They are clever animals with pointy ears and fluffy tails. They live in forests, grasslands, and even cities! Foxes are mostly active at night and have excellent hearing. Baby foxes are called kits.', 5),

('mammal', 'Giraffe', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/mammals/giraffe.png',
'This is a giraffe! Giraffes are mammals. They are the tallest animals in the world. Their long necks help them reach leaves high up in trees that other animals cannot get. Each giraffe has a unique pattern of spots, just like your fingerprints are unique to you!', 6),

('mammal', 'Lion', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/mammals/lion.png',
'This is a lion! Lions are mammals. They are big cats that live in Africa. They are called the "king of the jungle" because they are so powerful. Male lions have a fluffy mane around their head. Lions live in groups called prides.', 7),

('mammal', 'Monkey', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/mammals/monkey.png',
'This is a monkey! Monkeys are mammals. They are playful animals that love to climb trees and swing from branch to branch. They use their hands, feet, and sometimes their tails to hold on. Monkeys live in groups and like to groom each other.', 8),

('mammal', 'Rabbit', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/mammals/rabbit.png',
'This is a rabbit! Rabbits are mammals. They are soft, fluffy animals with long ears that help them hear very well. They hop around on their strong back legs and love to eat carrots and leafy greens. Rabbits can wiggle their noses super fast!', 9),

('mammal', 'Raccoon', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/mammals/raccoon.png',
'This is a raccoon! Raccoons are mammals. They have black masks around their eyes and striped tails. They are very clever and use their little hands to open things and find food. Raccoons come out at night and love to explore.', 10),

('mammal', 'Tiger', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/mammals/tiger.png',
'This is a tiger! Tigers are mammals. They are the biggest cats in the world. They have beautiful orange fur with black stripes - and every tiger has a different pattern! Tigers are powerful hunters and great swimmers.', 11),

('mammal', 'Whale', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/mammals/whale.png',
'This is a whale! Whales are mammals. They are the biggest animals on Earth - even bigger than dinosaurs were! Blue whales can be as long as three school buses. Even though they live in the ocean, whales breathe air just like us.', 12);

-- BIRDS (8)
INSERT INTO animals (type, name, image_url, narration_text, lesson_order) VALUES
('bird', 'Eagle', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/birds/eagle.png',
'This is an eagle! Eagles are birds. They are powerful birds with sharp eyes that can spot a rabbit from very far away. They have strong wings that let them soar high in the sky. The bald eagle is a symbol of America!', 1),

('bird', 'Flamingo', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/birds/flamingo.png',
'This is a flamingo! Flamingos are birds. They are tall pink birds that stand on one leg. They get their pink color from the shrimp and algae they eat. Flamingos live in big groups and do funny dances together.', 2),

('bird', 'Hummingbird', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/birds/hummingbird.png',
'This is a hummingbird! Hummingbirds are birds. They are tiny birds that can flap their wings super fast - up to 80 times per second! This makes a humming sound. They can fly backwards and hover in one spot like a helicopter.', 3),

('bird', 'Ostrich', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/birds/ostrich.png',
'This is an ostrich! Ostriches are birds. They are the biggest birds in the world, but they cannot fly. Instead, they run super fast - faster than any other bird! One ostrich egg is as big as 24 chicken eggs!', 4),

('bird', 'Owl', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/birds/owl.png',
'This is an owl! Owls are birds. They are nighttime birds with big round eyes that help them see in the dark. They can turn their heads almost all the way around to look behind them! Owls say "hoo hoo!"', 5),

('bird', 'Parrot', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/birds/parrot.png',
'This is a parrot! Parrots are birds. They are colorful birds that can learn to talk and copy sounds. They have strong curved beaks for cracking nuts and seeds. Some parrots can live for 80 years or more!', 6),

('bird', 'Peacock', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/birds/peacock.png',
'This is a peacock! Peacocks are birds. They are famous for their beautiful tail feathers that fan out like a rainbow. Only the male birds have these fancy feathers. The colorful spots on their feathers look like eyes!', 7),

('bird', 'Penguin', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/birds/penguin.png',
'This is a penguin! Penguins are birds. They are birds that cannot fly, but they are amazing swimmers! They waddle on land and zoom through the water like little torpedoes. Penguins live in cold places and huddle together to stay warm.', 8);

-- FISH (9)
INSERT INTO animals (type, name, image_url, narration_text, lesson_order) VALUES
('fish', 'Clownfish', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/fish/clownfish.png',
'This is a clownfish! Clownfish are fish. They are small orange fish with white stripes. They live inside sea anemones, which have stinging tentacles that protect the clownfish from predators. The clownfish and anemone are best friends!', 1),

('fish', 'Eel', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/fish/eel.png',
'This is an eel! Eels are fish. They are long, snake-like fish that can be found in oceans and rivers. Some eels can make electricity to zap their prey - these are called electric eels! Eels hide in rocks and caves during the day.', 2),

('fish', 'Goldfish', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/fish/goldfish.png',
'This is a goldfish! Goldfish are fish. They are popular pet fish that come in many colors - orange, white, red, and even black. Goldfish can remember things for months and can be trained to do simple tricks!', 3),

('fish', 'Manta Ray', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/fish/manta_ray.png',
'This is a manta ray! Manta rays are fish. They are huge flat fish that look like they are flying through the water. They have wide fins that flap like wings. Manta rays are gentle giants that eat tiny sea creatures.', 4),

('fish', 'Pufferfish', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/fish/pufferfish.png',
'This is a pufferfish! Pufferfish are fish. When a pufferfish gets scared, it puffs up into a big spiky ball! This makes it hard for other animals to eat it. They have cute little faces and swim in a funny wiggly way.', 5),

('fish', 'Seahorse', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/fish/seahorse.png',
'This is a seahorse! Seahorses are fish. They are tiny fish that look like little horses. They swim upright and use their curly tails to hold onto seaweed. Daddy seahorses carry the babies in a special pouch until they are born!', 6),

('fish', 'Shark', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/fish/shark.png',
'This is a shark! Sharks are fish. They are amazing fish that have been swimming in the ocean for millions of years - even before the dinosaurs! They have rows and rows of sharp teeth. Most sharks are not dangerous to people.', 7),

('fish', 'Swordfish', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/fish/swordfish.png',
'This is a swordfish! Swordfish are fish. They have a long, flat bill that looks like a sword. They use it to slash at fish they want to eat. Swordfish are super fast swimmers and can swim as fast as a car drives!', 8),

('fish', 'Tuna', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/fish/tuna.png',
'This is a tuna! Tuna are fish. They are strong, fast fish that never stop swimming their whole lives. They travel across entire oceans in big groups called schools. Tuna can swim as fast as 45 miles per hour!', 9);

-- REPTILES (6)
INSERT INTO animals (type, name, image_url, narration_text, lesson_order) VALUES
('reptile', 'Chameleon', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/reptiles/chameleon.png',
'This is a chameleon! Chameleons are reptiles. They are famous for changing colors. They do this to show their mood and to hide from predators. Chameleons have funny eyes that can look in two different directions at the same time!', 1),

('reptile', 'Crocodile', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/reptiles/crocodile.png',
'This is a crocodile! Crocodiles are reptiles. They are big reptiles with powerful jaws and lots of sharp teeth. They live in rivers and swamps in warm places. Crocodiles have been on Earth for 200 million years!', 2),

('reptile', 'Komodo Dragon', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/reptiles/komodo_dragon.png',
'This is a Komodo dragon! Komodo dragons are reptiles. They are the biggest lizards in the world - they can grow longer than a car! They live on a few islands in Indonesia. They are like real-life dragons!', 3),

('reptile', 'Lizard', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/reptiles/lizard.png',
'This is a lizard! Lizards are reptiles. They have four legs and long tails. Many lizards can drop their tails if a predator grabs them, and then grow a new one! Lizards love to sunbathe on warm rocks.', 4),

('reptile', 'Snake', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/reptiles/snake.png',
'This is a snake! Snakes are reptiles. They have no legs - they slither along the ground using their muscles. They smell with their tongues by flicking them in and out. Most snakes are harmless and help by eating mice.', 5),

('reptile', 'Turtle', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/reptiles/turtle.png',
'This is a turtle! Turtles are reptiles. They carry their homes on their backs - their shells protect them from danger. When scared, they can pull their head and legs inside. Turtles have been around since the time of dinosaurs!', 6);

-- AMPHIBIANS (3)
INSERT INTO animals (type, name, image_url, narration_text, lesson_order) VALUES
('amphibian', 'Frog', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/amphibians/frog.png',
'This is a frog! Frogs are amphibians. They can live both in water and on land. They start life as tadpoles swimming in ponds, then grow legs and hop onto land. Frogs catch flies with their long, sticky tongues. They say "ribbit ribbit!"', 1),

('amphibian', 'Salamander', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/amphibians/salamander.png',
'This is a salamander! Salamanders are amphibians. They look like lizards but have smooth, wet skin. They live in damp, cool places like under logs and rocks. Some salamanders can grow back body parts if they lose them!', 2),

('amphibian', 'Toad', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/amphibians/toad.png',
'This is a toad! Toads are amphibians. They are like frogs but have bumpy, dry skin and shorter legs. They spend more time on land than frogs do. Toads hop around gardens eating bugs and are very helpful!', 3);

-- INSECTS (8)
INSERT INTO animals (type, name, image_url, narration_text, lesson_order) VALUES
('insect', 'Ant', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/insects/ant.png',
'This is an ant! Ants are insects. They are tiny but super strong - they can carry things 50 times their own body weight! Ants live in big groups called colonies and work together to build tunnels and find food.', 1),

('insect', 'Bee', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/insects/bee.png',
'This is a bee! Bees are insects. They are very important insects that help flowers grow by spreading pollen. They live in hives and work together as a team. Bees make yummy honey! Bees do a special dance to tell other bees where to find flowers.', 2),

('insect', 'Beetle', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/insects/beetle.png',
'This is a beetle! Beetles are insects. They are the most common insects on Earth - there are more types of beetles than any other animal! They have hard wing covers that protect their flying wings underneath.', 3),

('insect', 'Butterfly', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/insects/butterfly.png',
'This is a butterfly! Butterflies are insects. They are beautiful insects with colorful wings. They start life as caterpillars, wrap themselves in a cocoon, and transform into butterflies - this is called metamorphosis!', 4),

('insect', 'Dragonfly', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/insects/dragonfly.png',
'This is a dragonfly! Dragonflies are insects. They are amazing fliers with four wings that can move separately. They can fly forwards, backwards, and hover in place like a helicopter! Dragonflies have huge eyes.', 5),

('insect', 'Firefly', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/insects/firefly.png',
'This is a firefly! Fireflies are insects. They are magical beetles that can make their bodies glow in the dark! They flash their lights at night to find friends. On summer nights, you can see them blinking like tiny stars!', 6),

('insect', 'Grasshopper', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/insects/grasshopper.png',
'This is a grasshopper! Grasshoppers are insects. They have long back legs that help them jump really far - up to 20 times their body length! They make chirping sounds by rubbing their legs against their wings.', 7),

('insect', 'Ladybug', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/insects/ladybug.png',
'This is a ladybug! Ladybugs are insects. They are small, round beetles with red wings and black spots. Gardeners love ladybugs because they eat aphids and other pests that hurt plants.', 8);

-- CRUSTACEANS (3)
INSERT INTO animals (type, name, image_url, narration_text, lesson_order) VALUES
('crustacean', 'Crab', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/crustaceans/crab.png',
'This is a crab! Crabs are crustaceans. They have hard shells and walk sideways on their eight legs. They have two big claws called pincers that they use to catch food and protect themselves. When crabs grow bigger, they shed their shell and grow a new one!', 1),

('crustacean', 'Lobster', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/crustaceans/lobster.png',
'This is a lobster! Lobsters are crustaceans. They are large crustaceans with long bodies and big claws. They live on the ocean floor and can live for a very long time - some lobsters are over 100 years old!', 2),

('crustacean', 'Shrimp', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/animals/crustaceans/shrimp.png',
'This is a shrimp! Shrimp are crustaceans. They are small crustaceans that live in oceans and rivers all around the world. They have long antennae and can swim backwards very fast by flicking their tail!', 3);
