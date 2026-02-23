-- Foods seed data
-- 42 foods across 6 categories (matching Dream Cloud images)

-- FRUITS (13)
INSERT INTO foods (category, name, image_url, narration_text) VALUES
('fruit', 'Apple', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/fruit/apple.png',
'This is an apple! Apples are fruits that grow on trees. They can be red, green, or yellow. Apples are crunchy and sweet, and they are very healthy for you. There is a saying: "An apple a day keeps the doctor away!"'),

('fruit', 'Banana', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/fruit/bananas.png',
'This is a banana! Bananas are fruits that grow in bunches on tall plants. They have a yellow peel that you take off before eating. Bananas are soft and sweet, and they give you lots of energy. Monkeys love bananas!'),

('fruit', 'Orange', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/fruit/orange.png',
'This is an orange! Oranges are round fruits with a bumpy orange peel. Inside, they are juicy and sweet. Oranges are full of vitamin C, which helps keep you healthy. You can eat them or drink them as orange juice!'),

('fruit', 'Strawberries', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/fruit/strawberries.png',
'These are strawberries! Strawberries are small red fruits with tiny seeds on the outside. They are sweet and juicy. Strawberries grow close to the ground on little plants. They are delicious in smoothies and on top of cereal!'),

('fruit', 'Grapes', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/fruit/grapes.png',
'These are grapes! Grapes are small round fruits that grow in bunches on vines. They can be green, red, or purple. Grapes are sweet and juicy, and you can eat them as a snack. Dried grapes are called raisins!'),

('fruit', 'Watermelon', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/fruit/watermelon.png',
'This is a watermelon! Watermelons are big fruits with a green rind and red, juicy inside. They have black seeds that you can spit out! Watermelons are mostly water, which makes them perfect for hot summer days.'),

('fruit', 'Blueberries', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/fruit/blueberries.png',
'These are blueberries! Blueberries are tiny round fruits that are dark blue. They grow on bushes and are super healthy for your brain. You can eat them by the handful, put them in pancakes, or add them to yogurt!'),

('fruit', 'Pineapple', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/fruit/pineapple.png',
'This is a pineapple! Pineapples are tropical fruits with a spiky outside and sweet yellow inside. They grow on plants close to the ground, not on trees! Pineapples are juicy and taste like a tropical vacation.'),

('fruit', 'Peach', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/fruit/peach.png',
'This is a peach! Peaches are soft, fuzzy fruits that are orange and pink. They are very juicy and sweet. Peaches grow on trees and are ready to eat in the summer. They have a big pit in the middle called a stone.'),

('fruit', 'Cherries', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/fruit/cherries.png',
'These are cherries! Cherries are small round fruits that are usually red or dark purple. They grow in pairs on stems and have small pits inside. Cherries are sweet and perfect for snacking or putting on top of ice cream!'),

('fruit', 'Lemon', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/fruit/lemon.png',
'This is a lemon! Lemons are yellow fruits that are very sour! They grow on trees and are full of vitamin C. People use lemons to make lemonade, flavor food, and add to water. When life gives you lemons, make lemonade!'),

('fruit', 'Pear', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/fruit/pear.png',
'This is a pear! Pears are fruits that are shaped like teardrops or bells. They can be green, yellow, or red. Pears are sweet and juicy, and they grow on trees. They get softer and sweeter as they ripen!'),

('fruit', 'Raspberries', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/fruit/raspberries.png',
'These are raspberries! Raspberries are small red berries made of tiny little bumps called drupelets. They grow on bushes with thorns. Raspberries are sweet and a little tart. They are delicious fresh or in jam!');

-- VEGGIES (12)
INSERT INTO foods (category, name, image_url, narration_text) VALUES
('veggies', 'Carrots', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/veggies/carrots.png',
'These are carrots! Carrots are orange vegetables that grow underground. They are crunchy and a little sweet. Carrots are great for your eyes because they have vitamin A. Rabbits love carrots, and so should you!'),

('veggies', 'Broccoli', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/veggies/broccoli.png',
'This is broccoli! Broccoli looks like a tiny tree that you can eat. It is green and full of vitamins that make you strong. You can eat broccoli raw, steamed, or roasted. It is one of the healthiest vegetables!'),

('veggies', 'Corn', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/veggies/corn.png',
'This is corn! Corn grows on tall stalks and comes in ears wrapped in green husks. The yellow kernels are sweet and yummy. You can eat corn on the cob, or the kernels by themselves. Popcorn is made from corn too!'),

('veggies', 'Tomato', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/veggies/tomato.png',
'This is a tomato! Tomatoes are red and juicy. Even though we call them vegetables, they are actually fruits! Tomatoes are used to make ketchup, pasta sauce, and salsa. They grow on vines in gardens.'),

('veggies', 'Potato', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/veggies/potato.png',
'This is a potato! Potatoes are vegetables that grow underground. They have brown skin and white or yellow inside. You can make so many things with potatoes: french fries, mashed potatoes, baked potatoes, and chips!'),

('veggies', 'Cucumber', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/veggies/cucumber.png',
'This is a cucumber! Cucumbers are long green vegetables that are crunchy and refreshing. They are mostly made of water! Cucumbers are great in salads and sandwiches. Pickles are made from cucumbers!'),

('veggies', 'Lettuce', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/veggies/lettuce.png',
'This is lettuce! Lettuce is a leafy green vegetable with crunchy leaves. It is the main ingredient in salads. Lettuce is light and refreshing, and it gives a nice crunch to sandwiches and tacos!'),

('veggies', 'Peas', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/veggies/peas.png',
'These are peas! Peas are small round green vegetables that grow inside pods. They are sweet and fun to pop out of their pods. Peas are full of protein and vitamins. You can eat them fresh, frozen, or in soup!'),

('veggies', 'Green Beans', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/veggies/green_beans.png',
'These are green beans! Green beans are long, thin green vegetables. You eat the whole thing, pod and all! They are crunchy when fresh and tender when cooked. Green beans grow on vines or bushes.'),

('veggies', 'Onions', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/veggies/onions.png',
'These are onions! Onions are round vegetables with layers inside, like a ball made of rings. They can make your eyes water when you cut them! Onions add lots of flavor to cooking. They can be white, yellow, or red.'),

('veggies', 'Celery', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/veggies/celery.png',
'This is celery! Celery is a long, crunchy green vegetable. It has strings inside called fibers. Celery is mostly water and makes a great healthy snack. Try it with peanut butter on top!'),

('veggies', 'Pumpkin', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/veggies/pumpkin.png',
'This is a pumpkin! Pumpkins are big orange vegetables that grow on vines. People carve them into jack-o-lanterns for Halloween! But pumpkins are also delicious in pies, soups, and breads. The seeds are tasty too!');

-- MEAT (5)
INSERT INTO foods (category, name, image_url, narration_text) VALUES
('meat', 'Chicken', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/meat/chicken.png',
'This is chicken! Chicken is a type of meat that comes from chickens, which are birds raised on farms. It is white meat that can be cooked in many ways: baked, grilled, or fried. Chicken gives you protein to grow strong!'),

('meat', 'Steak', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/meat/steak.png',
'This is steak! Steak is meat that comes from cows raised on farms and ranches. It is red meat that turns brown when cooked. Steak is often grilled or pan-fried. It has lots of protein and iron to help you grow strong!'),

('meat', 'Pork', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/meat/pork.png',
'This is pork! Pork is meat that comes from pigs raised on farms. It can be made into many foods like pork chops, ham, and bacon. Pork is sometimes called "the other white meat" because it is light colored when cooked.'),

('meat', 'Fish', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/meat/fish.png',
'This is fish! Fish is meat that comes from fish caught in oceans, lakes, and rivers. It is very healthy because it has good fats that help your brain. There are many kinds of fish you can eat, like salmon and tuna!'),

('meat', 'Turkey', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/meat/turkey.png',
'This is turkey! Turkey is meat that comes from turkeys, which are big birds. Many families eat turkey for Thanksgiving dinner! Turkey is lean meat, which means it has lots of protein but not too much fat.');

-- GRAINS (3)
INSERT INTO foods (category, name, image_url, narration_text) VALUES
('grains', 'Wheat', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/grains/wheat.png',
'This is wheat! Wheat is a grain that grows in fields as tall golden stalks. The seeds are ground up to make flour, which is used to bake bread, pasta, and cookies. Wheat is one of the most important foods in the world!'),

('grains', 'Rice', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/grains/rice.png',
'This is rice! Rice is a grain that grows in wet fields called paddies. It is small and white or brown. Rice is eaten by people all over the world, especially in Asia. It is fluffy and goes well with many foods!'),

('grains', 'Oats', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/grains/oats.png',
'These are oats! Oats are grains that grow in fields. They are used to make oatmeal, a warm and cozy breakfast. Oats are also in granola and oatmeal cookies. They are full of fiber that is good for your tummy!');

-- DAIRY (4)
INSERT INTO foods (category, name, image_url, narration_text) VALUES
('dairy', 'Milk', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/dairy/milk.png',
'This is milk! Milk is a white liquid that comes from cows. It is full of calcium, which makes your bones and teeth strong. You can drink milk plain, with cookies, or in cereal. Babies drink milk to grow big and strong!'),

('dairy', 'Cheese', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/dairy/cheese.png',
'This is cheese! Cheese is made from milk. There are hundreds of different types of cheese, like cheddar, mozzarella, and swiss. Cheese can be soft or hard, mild or strong. It is delicious on pizza, sandwiches, and crackers!'),

('dairy', 'Egg', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/dairy/egg.png',
'This is an egg! Eggs come from chickens and other birds. The yellow part is called the yolk and the white part is called the white. You can fry, scramble, boil, or bake eggs. They are full of protein!'),

('dairy', 'Butter', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/dairy/butter.png',
'This is butter! Butter is made from cream, which comes from milk. It is yellow and creamy. Butter makes food taste rich and delicious. It is used in baking and for spreading on toast and bread!');

-- NUTS (5)
INSERT INTO foods (category, name, image_url, narration_text) VALUES
('nuts', 'Peanuts', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/nuts/peanuts.png',
'These are peanuts! Peanuts actually grow underground, not on trees like other nuts. They have a crunchy shell with two peanuts inside. Peanuts are made into peanut butter, which is delicious on sandwiches!'),

('nuts', 'Almonds', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/nuts/almonds.png',
'These are almonds! Almonds are nuts that grow on trees. They have a tan shell and are crunchy and slightly sweet. Almonds are very healthy for your heart. You can eat them whole or drink almond milk!'),

('nuts', 'Walnuts', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/nuts/walnuts.png',
'These are walnuts! Walnuts have a hard, bumpy shell and the nut inside looks like a tiny brain! They are crunchy and have a rich flavor. Walnuts are good for your brain and heart. They are great in brownies!'),

('nuts', 'Pistachios', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/nuts/pistachios.png',
'These are pistachios! Pistachios are green nuts in tan shells that are partly open. You can pop them open to eat the nut inside. Pistachios are fun to eat and are often used in ice cream and desserts!'),

('nuts', 'Pecans', 'https://lfpzverpjlcuobmgejwv.supabase.co/storage/v1/object/public/food/nuts/pecans.png',
'These are pecans! Pecans are brown nuts with a buttery, sweet flavor. They grow on pecan trees, mostly in the southern United States. Pecans are famous for being in pecan pie, a delicious dessert!');
