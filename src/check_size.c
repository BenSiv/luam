#include "lobject.h"
#include "lstate.h"
#include "lua.h"
#include <stdio.h>

int main() {
  printf("C TValue size: %zu\n", sizeof(TValue));
  printf("C Table size: %zu\n", sizeof(Table));
  printf("C Node size: %zu\n", sizeof(Node));
  printf("C LClosure size: %zu\n", sizeof(LClosure));
  printf("C lua_State size: %zu\n", sizeof(lua_State));
  printf("C GCObject size: %zu\n", sizeof(GCObject));
  return 0;
}
