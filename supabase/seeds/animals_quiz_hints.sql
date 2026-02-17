-- Quiz hints for animals - descriptions that don't reveal the name
-- Format: "This is a [type], it [description]..."

-- MAMMALS
UPDATE animals SET quiz_hint = 'This is a mammal. It is big and furry, lives in forests and mountains, and sleeps all winter long in a cozy den.' WHERE name = 'Bear';
UPDATE animals SET quiz_hint = 'This is a mammal. It is a furry pet that purrs, has soft paws with sharp claws, and can see very well in the dark.' WHERE name = 'Cat';
UPDATE animals SET quiz_hint = 'This is a mammal. It lives in the ocean but breathes air, is very playful and smart, and talks using clicks and whistles.' WHERE name = 'Dolphin';
UPDATE animals SET quiz_hint = 'This is a mammal. It is the largest animal on land, has a long trunk, and is known for having an amazing memory.' WHERE name = 'Elephant';
UPDATE animals SET quiz_hint = 'This is a mammal. It is clever with pointy ears and a fluffy tail, and is mostly active at night.' WHERE name = 'Fox';
UPDATE animals SET quiz_hint = 'This is a mammal. It is the tallest animal in the world, has a very long neck, and has a unique pattern of spots.' WHERE name = 'Giraffe';
UPDATE animals SET quiz_hint = 'This is a mammal. It is a big cat from Africa called the king of the jungle, and the males have a fluffy mane.' WHERE name = 'Lion';
UPDATE animals SET quiz_hint = 'This is a mammal. It is playful, loves to climb trees and swing from branches, and lives in groups.' WHERE name = 'Monkey';
UPDATE animals SET quiz_hint = 'This is a mammal. It is soft and fluffy with long ears, hops on strong back legs, and loves to eat carrots.' WHERE name = 'Rabbit';
UPDATE animals SET quiz_hint = 'This is a mammal. It has a black mask around its eyes, a striped tail, and comes out at night to explore.' WHERE name = 'Raccoon';
UPDATE animals SET quiz_hint = 'This is a mammal. It is the biggest cat in the world, has orange fur with black stripes, and is a great swimmer.' WHERE name = 'Tiger';
UPDATE animals SET quiz_hint = 'This is a mammal. It is the biggest animal on Earth, lives in the ocean, and breathes air through a blowhole.' WHERE name = 'Whale';

-- BIRDS
UPDATE animals SET quiz_hint = 'This is a bird. It is powerful with sharp eyes, soars high in the sky, and is a symbol of America.' WHERE name = 'Eagle';
UPDATE animals SET quiz_hint = 'This is a bird. It is tall and pink, stands on one leg, and gets its color from eating shrimp.' WHERE name = 'Flamingo';
UPDATE animals SET quiz_hint = 'This is a bird. It is tiny, flaps its wings super fast making a humming sound, and can fly backwards.' WHERE name = 'Hummingbird';
UPDATE animals SET quiz_hint = 'This is a bird. It is the biggest bird in the world, cannot fly, but can run faster than any other bird.' WHERE name = 'Ostrich';
UPDATE animals SET quiz_hint = 'This is a bird. It has big round eyes, comes out at night, and can turn its head almost all the way around.' WHERE name = 'Owl';
UPDATE animals SET quiz_hint = 'This is a bird. It is colorful, can learn to talk and copy sounds, and has a strong curved beak.' WHERE name = 'Parrot';
UPDATE animals SET quiz_hint = 'This is a bird. It is famous for beautiful tail feathers that fan out like a rainbow with spots that look like eyes.' WHERE name = 'Peacock';
UPDATE animals SET quiz_hint = 'This is a bird. It cannot fly but is an amazing swimmer, waddles on land, and lives in cold places.' WHERE name = 'Penguin';

-- FISH
UPDATE animals SET quiz_hint = 'This is a fish. It is small and orange with white stripes, and lives inside sea anemones.' WHERE name = 'Clownfish';
UPDATE animals SET quiz_hint = 'This is a fish. It is long and snake-like, hides in rocks and caves, and some can make electricity.' WHERE name = 'Eel';
UPDATE animals SET quiz_hint = 'This is a fish. It is a popular pet that comes in many colors like orange, white, and red, and can be trained to do tricks.' WHERE name = 'Goldfish';
UPDATE animals SET quiz_hint = 'This is a fish. It is huge and flat, looks like it is flying through the water, and has wide fins that flap like wings.' WHERE name = 'Manta Ray';
UPDATE animals SET quiz_hint = 'This is a fish. When it gets scared, it puffs up into a big spiky ball to protect itself.' WHERE name = 'Pufferfish';
UPDATE animals SET quiz_hint = 'This is a fish. It is tiny and looks like a little horse, swims upright, and uses its curly tail to hold onto seaweed.' WHERE name = 'Seahorse';
UPDATE animals SET quiz_hint = 'This is a fish. It has rows of sharp teeth, has been swimming in the ocean for millions of years, even before dinosaurs.' WHERE name = 'Shark';
UPDATE animals SET quiz_hint = 'This is a fish. It has a long flat bill that looks like a sword and is a super fast swimmer.' WHERE name = 'Swordfish';
UPDATE animals SET quiz_hint = 'This is a fish. It is strong and fast, never stops swimming its whole life, and travels across oceans in big groups.' WHERE name = 'Tuna';

-- REPTILES
UPDATE animals SET quiz_hint = 'This is a reptile. It can change colors, has eyes that look in two different directions at once, and catches bugs with its tongue.' WHERE name = 'Chameleon';
UPDATE animals SET quiz_hint = 'This is a reptile. It has powerful jaws with lots of sharp teeth, lives in rivers and swamps, and has been on Earth for 200 million years.' WHERE name = 'Crocodile';
UPDATE animals SET quiz_hint = 'This is a reptile. It is the biggest lizard in the world, can grow longer than a car, and lives on islands in Indonesia.' WHERE name = 'Komodo Dragon';
UPDATE animals SET quiz_hint = 'This is a reptile. It has four legs and a long tail, can drop its tail and grow a new one, and loves to sunbathe on warm rocks.' WHERE name = 'Lizard';
UPDATE animals SET quiz_hint = 'This is a reptile. It has no legs and slithers along the ground, smells with its tongue, and most are harmless.' WHERE name = 'Snake';
UPDATE animals SET quiz_hint = 'This is a reptile. It carries its home on its back, can pull its head and legs inside its shell, and has been around since dinosaur times.' WHERE name = 'Turtle';

-- AMPHIBIANS
UPDATE animals SET quiz_hint = 'This is an amphibian. It starts life as a tadpole, then grows legs and hops on land, and catches flies with its sticky tongue.' WHERE name = 'Frog';
UPDATE animals SET quiz_hint = 'This is an amphibian. It looks like a lizard but has smooth wet skin, lives in damp cool places, and can grow back body parts.' WHERE name = 'Salamander';
UPDATE animals SET quiz_hint = 'This is an amphibian. It is like a frog but has bumpy dry skin and shorter legs, and spends more time on land.' WHERE name = 'Toad';

-- INSECTS
UPDATE animals SET quiz_hint = 'This is an insect. It is tiny but super strong, can carry 50 times its body weight, and lives in colonies with tunnels.' WHERE name = 'Ant';
UPDATE animals SET quiz_hint = 'This is an insect. It helps flowers grow by spreading pollen, makes honey, and does a special dance to tell friends where flowers are.' WHERE name = 'Bee';
UPDATE animals SET quiz_hint = 'This is an insect. It is the most common type of insect on Earth and has hard wing covers protecting its flying wings.' WHERE name = 'Beetle';
UPDATE animals SET quiz_hint = 'This is an insect. It has colorful wings, starts life as a caterpillar, and transforms in a cocoon.' WHERE name = 'Butterfly';
UPDATE animals SET quiz_hint = 'This is an insect. It has four wings, can fly backwards and hover like a helicopter, and has huge eyes.' WHERE name = 'Dragonfly';
UPDATE animals SET quiz_hint = 'This is an insect. It can make its body glow in the dark and flashes lights at night like tiny stars.' WHERE name = 'Firefly';
UPDATE animals SET quiz_hint = 'This is an insect. It has long back legs that help it jump really far and makes chirping sounds by rubbing its legs.' WHERE name = 'Grasshopper';
UPDATE animals SET quiz_hint = 'This is an insect. It is small and round with red wings and black spots, and gardeners love it because it eats pests.' WHERE name = 'Ladybug';

-- CRUSTACEANS
UPDATE animals SET quiz_hint = 'This is a crustacean. It has a hard shell, walks sideways on eight legs, and has two big claws called pincers.' WHERE name = 'Crab';
UPDATE animals SET quiz_hint = 'This is a crustacean. It is large with a long body and big claws, lives on the ocean floor, and can live over 100 years.' WHERE name = 'Lobster';
UPDATE animals SET quiz_hint = 'This is a crustacean. It is small with long antennae and can swim backwards very fast by flicking its tail.' WHERE name = 'Shrimp';
