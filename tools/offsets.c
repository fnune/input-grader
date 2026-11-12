#include <stddef.h>
#include <stdio.h>
#include "structs.h"
int main(void) {
  printf("WORK rl_flag %zu rl_waza %zu xyz %zu\n", offsetof(WORK, rl_flag), offsetof(WORK, rl_waza), offsetof(WORK, xyz));
  printf("PLW wu %zu player_number %zu sa_stop_flag %zu do_not_move %zu\n", offsetof(PLW, wu), offsetof(PLW, player_number), offsetof(PLW, sa_stop_flag), offsetof(PLW, do_not_move));
  printf("WORK routine_no %zu old_rno %zu\n", offsetof(WORK, routine_no), offsetof(WORK, old_rno));
  printf("sizeof WORK_CP %zu WAZA_WORK %zu\n", sizeof(WORK_CP), sizeof(WAZA_WORK));
  return 0;
}
