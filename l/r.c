 /* r.c
 *
 * R — a micro text adventure built from fractured language.
 * Every word you wrote becomes the world: rooms, items, and enemies.
 *
 * Compile:
 *     gcc -std=c11 -O2 -Wall -o r r.c
 * Run:
 *     ./r
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <ctype.h>

#define MAX_LINES 128
#define MAX_WORDS_PER_ROOM 64
#define MAX_WORD_LEN 64
#define MAX_INVENTORY 32

static const char *SOURCE_TEXT =
"Dreiouaux\n"
" doesquiex\n"
"  st tf I as try\n"
"  had set tree at\n"
"  hot dr \n"
"   hr at t\n"
"   if d far uh hi of\n"
"    Gf d bf at yuh gf d do us dry uh Nd do um \n"
" if by r gf gf \n"
"    Hey ty\n"
"   gf to garage to song do off do bd to bf to bro if ty hit do t\n";

typedef struct {
    char word[MAX_WORD_LEN];
    int hp;
    int attack;
    int is_item;
} Entity;

typedef struct {
    char line_text[256];
    Entity entities[MAX_WORDS_PER_ROOM];
    int entity_count;
} Room;

typedef struct {
    char name[64];
    int hp;
    int max_hp;
    int pos;
    char inventory[MAX_INVENTORY][MAX_WORD_LEN];
    int inv_count;
} Player;

void parse_line_to_room(const char *line, Room *room) {
    room->entity_count = 0;
    strncpy(room->line_text, line, sizeof(room->line_text)-1);
    room->line_text[sizeof(room->line_text)-1] = '\0';

    int i = 0, len = strlen(line);
    char buf[MAX_WORD_LEN];
    int b = 0;
    while (i <= len) {
        char c = line[i];
        if (isalpha((unsigned char)c)) {
            if (b < (MAX_WORD_LEN-1)) buf[b++] = c;
        } else {
            if (b > 0) {
                buf[b] = '\0';
                if (b >= 2 || (b==1 && buf[0]=='I')) {
                    if (room->entity_count < MAX_WORDS_PER_ROOM) {
                        Entity *e = &room->entities[room->entity_count++];
                        strncpy(e->word, buf, MAX_WORD_LEN-1);
                        e->word[MAX_WORD_LEN-1] = '\0';
                        int wl = strlen(e->word);
                        char last = tolower((unsigned char)e->word[wl-1]);
                        int is_item = (last=='e'||last=='t'||last=='y'||wl<=3);
                        if (isupper((unsigned char)e->word[0]) && wl>2) is_item = 0;
                        e->is_item = is_item;
                        e->hp = 1 + wl * (is_item ? 0 : 2);
                        e->attack = 1 + wl/2;
                    }
                }
                b = 0;
            }
        }
        i++;
    }
}

int init_rooms(Room rooms[], int max_rooms) {
    char copy[strlen(SOURCE_TEXT)+1];
    strcpy(copy, SOURCE_TEXT);
    int idx = 0;
    char *line = strtok(copy, "\n");
    while (line && idx < max_rooms) {
        parse_line_to_room(line, &rooms[idx++]);
        line = strtok(NULL, "\n");
    }
    return idx;
}

int roll(int min, int max) { return min + rand() % (max - min + 1); }

void print_status(Player *p, int room_count) {
    printf("\n=== R ===\n");
    printf("%s | HP %d/%d | Room %d/%d\n",
           p->name, p->hp, p->max_hp, p->pos+1, room_count);
    printf("-----------\n");
}

void inspect_room(Room *r) {
    printf("\nYou look around:\n%s\n", r->line_text);
    if (r->entity_count == 0) { printf("(nothing moves)\n"); return; }
    for (int i=0;i<r->entity_count;++i) {
        Entity *e = &r->entities[i];
        printf(" [%2d] %-16s %s HP:%d ATK:%d\n",
               i+1, e->word, e->is_item?"(item)":"(enemy)", e->hp, e->attack);
    }
}

void show_inventory(Player *p) {
    printf("\nInventory:\n");
    if (p->inv_count==0) { printf("(empty)\n"); return; }
    for (int i=0;i<p->inv_count;++i)
        printf(" [%2d] %s\n", i+1, p->inventory[i]);
}

void take_entity(Player *p, Room *r, int idx) {
    if (idx<0||idx>=r->entity_count) return;
    Entity *e = &r->entities[idx];
    if (p->inv_count>=MAX_INVENTORY) { printf("Inventory full.\n"); return; }
    strncpy(p->inventory[p->inv_count++], e->word, MAX_WORD_LEN-1);
    printf("You picked up %s.\n", e->word);
    for (int k=idx;k+1<r->entity_count;++k) r->entities[k]=r->entities[k+1];
    r->entity_count--;
}

void use_item(Player *p, int idx) {
    if (idx<0||idx>=p->inv_count) return;
    char *w = p->inventory[idx];
    int heal = strlen(w)<5 ? 4 : 8;
    int old = p->hp;
    p->hp += heal;
    if (p->hp > p->max_hp) p->hp = p->max_hp;
    printf("You use %s. (+%d HP)\n", w, p->hp-old);
    for (int i=idx;i+1<p->inv_count;++i)
        strncpy(p->inventory[i], p->inventory[i+1], MAX_WORD_LEN);
    p->inv_count--;
}

void attack_entity(Player *p, Room *r, int idx) {
    if (idx<0||idx>=r->entity_count) return;
    Entity *e = &r->entities[idx];
    if (e->is_item) { printf("You grab %s instead.\n", e->word); take_entity(p,r,idx); return; }
    printf("You swing at %s!\n", e->word);
    int dmg = roll(2,5);
    e->hp -= dmg;
    printf("You deal %d damage.\n", dmg);
    if (e->hp<=0) {
        printf("%s collapses.\n", e->word);
        if (roll(1,100)<=40 && p->inv_count<MAX_INVENTORY) {
            char shard[MAX_WORD_LEN];
            snprintf(shard,sizeof(shard),"%s_frag", e->word);
            strncpy(p->inventory[p->inv_count++], shard, MAX_WORD_LEN-1);
            printf("You find %s.\n", shard);
        }
        for (int k=idx;k+1<r->entity_count;++k) r->entities[k]=r->entities[k+1];
        r->entity_count--;
    } else {
        int hurt = roll(1,e->attack);
        p->hp -= hurt;
        printf("%s retaliates for %d damage.\n", e->word, hurt);
    }
}

int main(void) {
    srand((unsigned)time(NULL));
    Room rooms[MAX_LINES];
    int room_count = init_rooms(rooms, MAX_LINES);
    if (!room_count) { printf("No world to load.\n"); return 0; }

    Player p = {0};
    printf("Enter your name:\n> ");
    fgets(p.name,sizeof(p.name),stdin);
    p.name[strcspn(p.name,"\r\n")]=0;
    if (!*p.name) strcpy(p.name,"You");

    p.hp = p.max_hp = 20;
    p.pos = 0;

    printf("\nYou awaken. The floor is cold.\n");
    printf("Type 'i' to look around.\n");

    while (p.hp>0) {
        print_status(&p, room_count);
        printf("Action (n,p,i,a,t,v,u,q): ");
        int c = getchar();
        while (c=='\n'||c=='\r') c=getchar();
        if (c=='q') break;
        if (c=='n'&&p.pos<room_count-1){p.pos++;printf("You move forward.\n");}
        else if (c=='p'&&p.pos>0){p.pos--;printf("You move back.\n");}
        else if (c=='i') inspect_room(&rooms[p.pos]);
        else if (c=='v') show_inventory(&p);
        else if (c=='t'){ inspect_room(&rooms[p.pos]); printf("Take which? "); int idx; scanf("%d",&idx); getchar(); take_entity(&p,&rooms[p.pos],idx-1); }
        else if (c=='a'){ inspect_room(&rooms[p.pos]); printf("Attack which? "); int idx; scanf("%d",&idx); getchar(); attack_entity(&p,&rooms[p.pos],idx-1); }
        else if (c=='u'){ show_inventory(&p); printf("Use which? "); int idx; scanf("%d",&idx); getchar(); use_item(&p,idx-1); }
        else printf("...\n");

        if (p.pos==room_count-1 && rooms[p.pos].entity_count==0) {
            printf("\nYou reach the end. Silence.\n");
            break;
        }
        if (p.hp<=0) printf("\nYou fall. Dead on the floor.\n");
    }

    printf("\nGame over — R.\n");
    return 0;
}
