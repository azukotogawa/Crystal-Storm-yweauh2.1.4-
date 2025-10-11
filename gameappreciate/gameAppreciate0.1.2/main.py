from settings import *
from player import Player
from sprites import *
from pytmx.util_pygame import load_pygame
from groups import AllSprites
from test_generate_world import *
from test_generate_world import *

from random import randint

# general setup
class Game:
    def __init__(self):
        #setup
        pygame.init()
        self.display_surface = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT))
        pygame.display.set_caption('gameAppreciate')
        self.clock = pygame.time.Clock()
        self.running = True

        #groups
        self.all_sprites = AllSprites()
        self.collision_sprites = pygame.sprite.Group()

        self.setup()

    def setup(self):
        map = load_pygame(join('../', 'data', 'maps', 'world.tmx'))
        #for x,y, image in map.get_layer_by_name('Ground').tiles():
        #    Sprite((x * TILE_SIZE,y * TILE_SIZE), image, self.all_sprites)

        #for obj in map.get_layer_by_name('Objects'):
        #    CollisionSprite((obj.x, obj.y), obj.image, (self.all_sprites, self.collision_sprites))

        #for obj in map.get_layer_by_name('Collisions'):
        #    CollisionSprite((obj.x, obj.y), pygame.Surface((obj.width, obj.height)), self.collision_sprites)

        for obj in map.get_layer_by_name('Entities'):
            if obj.name == 'Player':
                self.player = Player((obj.x, obj.y), self.all_sprites, self.collision_sprites)

        self.worldload = WorldLoad(self.player.rect.center)

    def run(self):
        while self.running:
            #delta time
            dt = self.clock.tick() / 1000

            #event loop
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False

            #update
            self.all_sprites.update(dt)

            #draw
            self.display_surface.fill('black')
            #draw world
            self.worldload.draw(self.player.rect.center)
            
            self.all_sprites.draw(self.player.rect.center)
            pygame.display.update()

        pygame.quit()

if __name__ == '__main__':
    game = Game()
    game.run()

# importing an image
#If the image has no transparent pixels: .covert
#If the image has transparent pixels: .convert_alpha
#image_surf = pygame.image.load(join('resources', 'button.bmp')).convert()
    # draw the game

    #display_surface.blit(image_surf, (0, 0))
    #pygame.display.update()