#include <stddef.h>
#include <stdio.h>
#include "structs.h"
int main(void) {
  printf("WORK rl_flag %zu rl_waza %zu xyz %zu\n", offsetof(WORK, rl_flag), offsetof(WORK, rl_waza), offsetof(WORK, xyz));
  printf("PLW wu %zu player_number %zu sa_stop_flag %zu do_not_move %zu\n", offsetof(PLW, wu), offsetof(PLW, player_number), offsetof(PLW, sa_stop_flag), offsetof(PLW, do_not_move));
  printf("WORK routine_no %zu old_rno %zu size %zu\n", offsetof(WORK, routine_no), offsetof(WORK, old_rno), sizeof(((WORK*)0)->routine_no[0]));
  printf("WORK cg_ctr %zu cg_type %zu cg_cancel %zu meoshi_hit_flag %zu\n", offsetof(WORK, cg_ctr), offsetof(WORK, cg_type), offsetof(WORK, cg_cancel), offsetof(WORK, meoshi_hit_flag));
  printf("PLW tsukamarenai_flag %zu cancel_timer %zu permited_koa %zu\n", offsetof(PLW, tsukamarenai_flag), offsetof(PLW, cancel_timer), offsetof(PLW, permited_koa));
  printf("WORK shell_ix %zu original_vitality %zu WORK_Other refrected %zu\n", offsetof(WORK, shell_ix), offsetof(WORK, original_vitality), offsetof(WORK_Other, refrected));
  printf("PLW sa %zu SA_WORK ok %zu mp %zu ex %zu store %zu\n", offsetof(PLW, sa), offsetof(SA_WORK, ok), offsetof(SA_WORK, mp), offsetof(SA_WORK, ex), offsetof(SA_WORK, store));
  printf("sizeof WORK_CP %zu WAZA_WORK %zu\n", sizeof(WORK_CP), sizeof(WAZA_WORK));
  return 0;
}
