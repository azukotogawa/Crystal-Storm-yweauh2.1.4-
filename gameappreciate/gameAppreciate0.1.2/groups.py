from string import whitespace

from settings import *

class AllSprites(pygame.sprite.Group):
    def __init__(self):
        super().__init__()
        self.display_surface = pygame.display.get_surface()
        self.offset = pygame.Vector2()

    def draw(self, target_pos):
        self.offset.x = -(target_pos[0] - WINDOW_WIDTH / 2)
        self.offset.y = -(target_pos[1] - WINDOW_HEIGHT / 2)
        for sprite in self:
            self.display_surface.blit(sprite.image, sprite.rect.topleft + self.offset)

            font = pygame.font.Font('freesansbold.ttf', 32)
            white = (255, 255, 255)
            pos = int(target_pos[0]), int(target_pos[1])
            string = ' '.join(str(value) for value in pos)
            text = font.render(string, True, white)
            text_rect = text.get_rect()
            text_rect.center = 100,50
            self.display_surface.blit(text, text_rect)
