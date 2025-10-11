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
        #map = load_pygame(join('data', 'maps', 'world.tmx'))
        #for x,y, image in map.get_layer_by_name('Ground').tiles():
        #    Sprite((x * TILE_SIZE,y * TILE_SIZE), image, self.all_sprites)

        #for obj in map.get_layer_by_name('Objects'):
        #    CollisionSprite((obj.x, obj.y), obj.image, (self.all_sprites, self.collision_sprites))

        #for obj in map.get_layer_by_name('Collisions'):
        #    CollisionSprite((obj.x, obj.y), pygame.Surface((obj.width, obj.height)), self.collision_sprites)

        #for obj in map.get_layer_by_name('Entities'):
            #if obj.name == 'Player':
                #self.player = Player((obj.x, obj.y), self.all_sprites, self.collision_sprites)
        self.player = Player((640, 640), self.all_sprites, self.collision_sprites)
        self.worldload = WorldLoad(self.player.rect.center)
        self.worldload.draw(self.player.rect.center)

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

            font = pygame.font.Font('freesansbold.ttf', 32)
            white = (255, 255, 255)
            pos = int(self.player.rect.center[0]), int(self.player.rect.center[1])
            string = ' '.join(str(value) for value in pos)
            text = font.render(string, True, white)
            text_rect = text.get_rect()
            text_rect.center = 100, 50
            self.display_surface.blit(text, text_rect)

            string2 = str(int(self.clock.get_fps()))
            text2 = font.render(string2, True, white)
            text_rect2 = text2.get_rect()
            text_rect2.center = 100, 100
            self.display_surface.blit(text2, text_rect2)

            pos2 = int(pos[0]) // TILESIZE, int(pos[1]) // TILESIZE
            string3 = ' '.join(str(value) for value in pos2)
            text3 = font.render(string3, True, white)
            text_rect3 = text3.get_rect()
            text_rect3.center = 100, 150
            self.display_surface.blit(text3, text_rect3)

            self.worldGenerated = self.worldload.returnWorld()
            x = int(pos[0]) // TILESIZE
            y = int(pos[1]) // TILESIZE
            string4 = str(self.worldGenerated.getTileTypeandHeight(x, y))
            text4 = font.render(string4, True, white)
            text_rect4 = text4.get_rect()
            text_rect4.center = 100,200
            self.display_surface.blit(text4, text_rect4)

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