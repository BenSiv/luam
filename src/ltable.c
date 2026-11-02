/*
** $Id: ltable.c,v 2.32.1.2 2007/12/28 15:32:23 roberto Exp $
** Lua tables (hash)
** See Copyright Notice in lua.h
*/


/*
** Implementation of tables (aka arrays, objects, or hash tables).
** Tables keep its elements in two parts: an array part and a hash part.
** Non-negative integer keys are all candidates to be kept in the array
** part. The actual size of the array is the largest `n' such that at
** least half the slots between 0 and n are in use.
** Hash uses a mix of chained scatter table with Brent's variation.
** A main invariant of these tables is that, if an element is not
** in its main position (i.e. the `original' position that its hash gives
** to it), then the colliding element is in its own main position.
** Hence even when the load factor reaches 100%, performance remains good.
**
** Luam: traversal order is defined -- integer keys in ascending order,
** then every other key in the order it was added (doc/table_order.md).
** The hash part's node block is followed by an `int' order array with one
** slot per node. Non-integer keys take slots from the front as they are
** added; integer keys take slots from the back and are sorted lazily,
** before a traversal, so that walking them from the back gives ascending
** keys. Each node records its slot in `ord'; a slot of -1 is a tombstone
** (its node was given to another key, or its key moved to the end).
** Integer keys in the array part need no slots: they are 1..sizearray,
** and every integer key in the hash part is below 1 or above sizearray.
*/

#include <math.h>
#include <string.h>

#define ltable_c
#define LUA_CORE

#include "lua.h"

#include "ldebug.h"
#include "ldo.h"
#include "lgc.h"
#include "lmem.h"
#include "lobject.h"
#include "lstate.h"
#include "ltable.h"


/*
** max size of array part is 2^MAXBITS
*/
#if LUAI_BITSINT > 26
#define MAXBITS		26
#else
#define MAXBITS		(LUAI_BITSINT-2)
#endif

#define MAXASIZE	(1 << MAXBITS)


#define hashpow2(t,n)      (gnode(t, lmod((n), sizenode(t))))
  
#define hashstr(t,str)  hashpow2(t, (str)->tsv.hash)
#define hashboolean(t,p)        hashpow2(t, p)


/*
** for some types, it is better to avoid modulus by power of 2, as
** they tend to have many 2 factors.
*/
#define hashmod(t,n)	(gnode(t, ((n) % ((sizenode(t)-1)|1))))


#define hashpointer(t,p)	hashmod(t, IntPoint(p))


/*
** number of ints inside a lua_Number
*/
#define numints		cast_int(sizeof(lua_Number)/sizeof(int))



#define dummynode		(&dummynode_)

static const Node dummynode_ = {
  {{NULL}, LUA_TNIL},  /* value */
  {{{NULL}, LUA_TNIL, -1, NULL}}  /* key */
};


#define gord(n)		((n)->i_key.nk.ord)
#define gorder(t)	(cast(int *, (t)->node + sizenode(t)))
#define ordercap(t)	(((t)->node == dummynode) ? 0 : sizenode(t))
#define orderfull(t)	((t)->nint + (t)->nother >= ordercap(t))
#define nodeindex(t,n)	(cast_int((n) - gnode(t, 0)))

/* slot of the j-th integer key (j = 0 is the smallest once sorted) */
#define intslot(t,j)	(sizenode(t) - 1 - (j))

/* the key of node `idx', known to be an integer key */
#define intkeyof(t,idx)	(nvalue(key2tval(gnode(t, idx))))

/* bytes in a node block: the nodes, then their order array */
#define nodeblocksize(size)	(cast(size_t, size) * (sizeof(Node) + sizeof(int)))


/* a number with no fractional part (and not an infinity) */
static int isintkey (const TValue *key) {
  lua_Number n;
  if (!ttisnumber(key)) return 0;
  n = nvalue(key);
  return luai_numeq(floor(n), n) && luai_numeq(n - n, 0);
}


/* give node `n' (which has no slot) the next slot for its kind of key */
static void appendslot (Table *t, Node *n) {
  int *order = gorder(t);
  int s;
  lua_assert(!orderfull(t) && gord(n) == -1);
  if (isintkey(key2tval(n))) {
    s = intslot(t, t->nint);
    if (t->nint > 0 && !t->intdirty) {  /* still ascending? */
      int prev = order[s + 1];
      if (prev < 0 || intkeyof(t, prev) > nvalue(key2tval(n)))
        t->intdirty = 1;
    }
    t->nint++;
  }
  else
    s = t->nother++;
  order[s] = nodeindex(t, n);
  gord(n) = s;
}


static void dropslot (Table *t, Node *n) {
  if (gord(n) >= 0) {
    gorder(t)[gord(n)] = -1;
    gord(n) = -1;
  }
}


/* heap sort helper: integer slots end up with keys descending, so that
** reading them from the back of the order array gives ascending keys */
#define intbefore(t,a,b)	(intkeyof(t, a) > intkeyof(t, b))

static void siftdown (Table *t, int *a, int root, int m) {
  for (;;) {
    int child = 2 * root + 1;
    int tmp;
    if (child >= m) return;
    if (child + 1 < m && intbefore(t, a[child], a[child + 1])) child++;
    if (!intbefore(t, a[root], a[child])) return;
    tmp = a[root]; a[root] = a[child]; a[child] = tmp;
    root = child;
  }
}


/* drop tombstones from the integer slots and sort them */
static void sortints (Table *t) {
  int cap = sizenode(t);
  int *order = gorder(t);
  int w = cap - 1;
  int r, m;
  int *a;
  for (r = cap - 1; r >= cap - t->nint; r--) {
    if (order[r] >= 0) order[w--] = order[r];
  }
  t->nint = cap - 1 - w;
  m = t->nint;
  a = order + cap - m;
  for (r = m / 2 - 1; r >= 0; r--) siftdown(t, a, r, m);
  for (r = m - 1; r > 0; r--) {
    int tmp = a[0]; a[0] = a[r]; a[r] = tmp;
    siftdown(t, a, 0, r);
  }
  for (r = 0; r < m; r++) gord(gnode(t, a[r])) = cast_int(a + r - order);
  t->intdirty = 0;
}


/*
** hash for lua_Numbers
*/
static Node *hashnum (const Table *t, lua_Number n) {
  unsigned int a[numints];
  int i;
  if (luai_numeq(n, 0))  /* avoid problems with -0 */
    return gnode(t, 0);
  memcpy(a, &n, sizeof(a));
  for (i = 1; i < numints; i++) a[0] += a[i];
  return hashmod(t, a[0]);
}



/*
** returns the `main' position of an element in a table (that is, the index
** of its hash value)
*/
static Node *mainposition (const Table *t, const TValue *key) {
  switch (ttype(key)) {
    case LUA_TNUMBER:
      return hashnum(t, nvalue(key));
    case LUA_TSTRING:
      return hashstr(t, rawtsvalue(key));
    case LUA_TBOOLEAN:
      return hashboolean(t, bvalue(key));
    case LUA_TLIGHTUSERDATA:
      return hashpointer(t, pvalue(key));
    default:
      return hashpointer(t, gcvalue(key));
  }
}


/*
** returns the index for `key' if `key' is an appropriate key to live in
** the array part of the table, -1 otherwise.
*/
static int arrayindex (const TValue *key) {
  if (ttisnumber(key)) {
    lua_Number n = nvalue(key);
    int k;
    lua_number2int(k, n);
    if (luai_numeq(cast_num(k), n))
      return k;
  }
  return -1;  /* `key' did not match some condition */
}


/*
** returns the hash node holding `key', for table traversals
*/
static Node *findnode (lua_State *L, Table *t, StkId key) {
  Node *n = mainposition(t, key);
  do {  /* check whether `key' is somewhere in the chain */
    /* key may be dead already, but it is ok to use it in `next' */
    if (luaO_rawequalObj(key2tval(n), key) ||
          (ttype(gkey(n)) == LUA_TDEADKEY && iscollectable(key) &&
           gcvalue(gkey(n)) == gcvalue(key))) {
      if (gord(n) >= 0) return n;
      break;
    }
    else n = gnext(n);
  } while (n);
  luaG_runerror(L, "invalid key to " LUA_QL("next"));  /* key not found */
  return NULL;  /* to avoid warnings */
}


static int pushnode (lua_State *L, Table *t, int idx, StkId key) {
  setobj2s(L, key, key2tval(gnode(t, idx)));
  setobj2s(L, key+1, gval(gnode(t, idx)));
  return 1;
}


/*
** Traversal goes through four phases: integer keys below 1 (hash part),
** the array part, integer keys above it (hash part), and then every other
** key in the order it was added.
*/
#define PH_LOWINT	0
#define PH_ARRAY	1
#define PH_HIGHINT	2
#define PH_OTHER	3

int luaH_next (lua_State *L, Table *t, StkId key) {
  int *order = gorder(t);
  int phase;
  int i = 0;  /* next array index to try */
  int j = 0;  /* next integer slot (PH_LOWINT, PH_HIGHINT) or other slot */
  int highfound = 0;  /* j already is the first integer slot above 0 */
  if (t->intdirty) sortints(t);
  if (ttisnil(key))  /* first iteration */
    phase = PH_LOWINT;
  else {
    int k = arrayindex(key);
    if (0 < k && k <= t->sizearray) {  /* is `key' inside array part? */
      phase = PH_ARRAY;
      i = k;
    }
    else {
      Node *n = findnode(L, t, key);
      int s = gord(n);
      if (s < t->nother) {
        phase = PH_OTHER;
        j = s + 1;
      }
      else {
        phase = (nvalue(key2tval(n)) <= 0) ? PH_LOWINT : PH_HIGHINT;
        j = intslot(t, s) + 1;  /* intslot is its own inverse */
        highfound = 1;
      }
    }
  }
  if (phase == PH_LOWINT) {
    for (; j < t->nint; j++) {
      int idx = order[intslot(t, j)];
      if (idx < 0) continue;
      if (intkeyof(t, idx) > 0) break;
      if (!ttisnil(gval(gnode(t, idx)))) return pushnode(L, t, idx, key);
    }
    highfound = 1;
    phase = PH_ARRAY;
  }
  if (phase == PH_ARRAY) {
    for (; i < t->sizearray; i++) {
      if (!ttisnil(&t->array[i])) {  /* a non-nil value? */
        setnvalue(key, cast_num(i+1));
        setobj2s(L, key+1, &t->array[i]);
        return 1;
      }
    }
    if (!highfound) {  /* skip the integer keys below 1 */
      for (j = 0; j < t->nint; j++) {
        int idx = order[intslot(t, j)];
        if (idx >= 0 && intkeyof(t, idx) > 0) break;
      }
    }
    phase = PH_HIGHINT;
  }
  if (phase == PH_HIGHINT) {
    for (; j < t->nint; j++) {
      int idx = order[intslot(t, j)];
      if (idx >= 0 && !ttisnil(gval(gnode(t, idx))))
        return pushnode(L, t, idx, key);
    }
    j = 0;
  }
  for (; j < t->nother; j++) {
    int idx = order[j];
    if (idx >= 0 && !ttisnil(gval(gnode(t, idx))))
      return pushnode(L, t, idx, key);
  }
  return 0;  /* no more elements */
}


/*
** {=============================================================
** Rehash
** ==============================================================
*/


static int computesizes (int nums[], int *narray) {
  int i;
  int twotoi;  /* 2^i */
  int a = 0;  /* number of elements smaller than 2^i */
  int na = 0;  /* number of elements to go to array part */
  int n = 0;  /* optimal size for array part */
  for (i = 0, twotoi = 1; twotoi/2 < *narray; i++, twotoi *= 2) {
    if (nums[i] > 0) {
      a += nums[i];
      if (a > twotoi/2) {  /* more than half elements present? */
        n = twotoi;  /* optimal size (till now) */
        na = a;  /* all elements smaller than n will go to array part */
      }
    }
    if (a == *narray) break;  /* all elements already counted */
  }
  *narray = n;
  lua_assert(*narray/2 <= na && na <= *narray);
  return na;
}


static int countint (const TValue *key, int *nums) {
  int k = arrayindex(key);
  if (0 < k && k <= MAXASIZE) {  /* is `key' an appropriate array index? */
    nums[ceillog2(k)]++;  /* count as such */
    return 1;
  }
  else
    return 0;
}


static int numusearray (const Table *t, int *nums) {
  int lg;
  int ttlg;  /* 2^lg */
  int ause = 0;  /* summation of `nums' */
  int i = 1;  /* count to traverse all array keys */
  for (lg=0, ttlg=1; lg<=MAXBITS; lg++, ttlg*=2) {  /* for each slice */
    int lc = 0;  /* counter */
    int lim = ttlg;
    if (lim > t->sizearray) {
      lim = t->sizearray;  /* adjust upper limit */
      if (i > lim)
        break;  /* no more elements to count */
    }
    /* count elements in range (2^(lg-1), 2^lg] */
    for (; i <= lim; i++) {
      if (!ttisnil(&t->array[i-1]))
        lc++;
    }
    nums[lg] += lc;
    ause += lc;
  }
  return ause;
}


static int numusehash (const Table *t, int *nums, int *pnasize) {
  int totaluse = 0;  /* total number of elements */
  int ause = 0;  /* summation of `nums' */
  int i = sizenode(t);
  while (i--) {
    Node *n = &t->node[i];
    if (!ttisnil(gval(n))) {
      ause += countint(key2tval(n), nums);
      totaluse++;
    }
  }
  *pnasize += ause;
  return totaluse;
}


static void setarrayvector (lua_State *L, Table *t, int size) {
  int i;
  luaM_reallocvector(L, t->array, t->sizearray, size, TValue);
  for (i=t->sizearray; i<size; i++)
     setnilvalue(&t->array[i]);
  t->sizearray = size;
}


static void setnodevector (lua_State *L, Table *t, int size) {
  int lsize;
  if (size == 0) {  /* no elements to hash part? */
    t->node = cast(Node *, dummynode);  /* use common `dummynode' */
    lsize = 0;
  }
  else {
    int i;
    lsize = ceillog2(size);
    if (lsize > MAXBITS)
      luaG_runerror(L, "table overflow");
    size = twoto(lsize);
    if (cast(size_t, size) + 1 > MAX_SIZET / (sizeof(Node) + sizeof(int)))
      luaM_toobig(L);
    t->node = cast(Node *, luaM_malloc(L, nodeblocksize(size)));
    for (i=0; i<size; i++) {
      Node *n = gnode(t, i);
      gnext(n) = NULL;
      setnilvalue(gkey(n));
      setnilvalue(gval(n));
      gord(n) = -1;
    }
  }
  t->lsizenode = cast_byte(lsize);
  t->lastfree = gnode(t, size);  /* all positions are free */
  t->nint = 0;
  t->nother = 0;
  t->intdirty = 0;
}


/* will this hash key live in an array part of size `nasize'? */
static int goestoarray (const TValue *key, int nasize) {
  int k = arrayindex(key);
  return 0 < k && k <= nasize;
}


static void resize (lua_State *L, Table *t, int nasize, int nhsize) {
  int i;
  int oldasize = t->sizearray;
  int oldhsize = t->lsizenode;
  int oldcap = ordercap(t);
  int oldnint = t->nint;
  int oldnother = t->nother;
  int nint = 0;
  int nother = 0;
  lu_byte intdirty = t->intdirty;
  Node *nold = t->node;  /* save old hash ... */
  int *oldorder = gorder(t);  /* ... and its order (unused if oldcap is 0) */
  if (nasize > oldasize)  /* array part must grow? */
    setarrayvector(L, t, nasize);
  /* create new hash part with appropriate size */
  setnodevector(L, t, nhsize);
  if (nasize < oldasize)  /* array part must shrink? */
    t->sizearray = nasize;
  /* Rank the keys that stay in the hash part, in their current order:
     oldorder[s] becomes the new rank of the key in slot s, or -1. Placing
     each key at its rank while reading the old nodes in memory order is
     faster than re-inserting them in traversal order. (Done only now that
     no allocation can fail and leave the old order overwritten.) */
  for (i = 0; i < oldnint; i++) {
    int s = oldcap - 1 - i;
    int idx = oldorder[s];
    if (idx >= 0 && !ttisnil(gval(nold + idx)) &&
        !goestoarray(key2tval(nold + idx), nasize))
      oldorder[s] = nint++;
    else
      oldorder[s] = -1;
  }
  for (i = 0; i < oldnother; i++) {
    int idx = oldorder[i];
    oldorder[i] = (idx >= 0 && !ttisnil(gval(nold + idx))) ? nother++ : -1;
  }
  /* re-insert elements from hash part, each into its ranked slot */
  t->nint = nint;
  t->nother = nother;
  t->intdirty = intdirty;
  t->placing = 1;
  for (i = twoto(oldhsize) - 1; i >= 0; i--) {
    Node *old = nold+i;
    if (!ttisnil(gval(old))) {
      TValue *p = luaH_set(L, t, key2tval(old));
      int rank;
      lua_assert(gord(old) >= 0);  /* every live key has a slot */
      rank = oldorder[gord(old)];
      setobjt2t(L, p, gval(old));
      if (rank >= 0) {  /* stays in the hash part (else: went to the array) */
        Node *n = cast(Node *, p);
        int s = isintkey(key2tval(old)) ? intslot(t, rank) : rank;
        gorder(t)[s] = nodeindex(t, n);
        gord(n) = s;
      }
    }
  }
  t->placing = 0;
  if (nasize < oldasize) {
    /* re-insert elements from vanishing slice */
    for (i=nasize; i<oldasize; i++) {
      if (!ttisnil(&t->array[i]))
        setobjt2t(L, luaH_setnum(L, t, i+1), &t->array[i]);
    }
    /* shrink array */
    luaM_reallocvector(L, t->array, oldasize, nasize, TValue);
  }
  if (nold != dummynode)
    luaM_freemem(L, nold, nodeblocksize(twoto(oldhsize)));  /* free old block */
}


void luaH_resizearray (lua_State *L, Table *t, int nasize) {
  int nsize = (t->node == dummynode) ? 0 : sizenode(t);
  resize(L, t, nasize, nsize);
}


/*
** `compact' is set when the order array ran out of slots. If that is
** because of tombstones, not because every slot holds a live key, the new
** hash part gets room for twice the live keys: a table that keeps deleting
** and re-adding keys then compacts at most once per as many insertions as
** it has keys.
*/
static void rehash (lua_State *L, Table *t, const TValue *ek, int compact) {
  int nasize, na, nh;
  int nums[MAXBITS+1];  /* nums[i] = number of keys between 2^(i-1) and 2^i */
  int i;
  int totaluse;
  for (i=0; i<=MAXBITS; i++) nums[i] = 0;  /* reset counts */
  nasize = numusearray(t, nums);  /* count keys in array part */
  totaluse = nasize;  /* all those keys are integer keys */
  totaluse += numusehash(t, nums, &nasize);  /* count keys in hash part */
  /* count extra key */
  nasize += countint(ek, nums);
  totaluse++;
  /* compute new size for array part */
  na = computesizes(nums, &nasize);
  nh = totaluse - na;
  if (compact && nh <= ordercap(t))
    nh *= 2;
  /* resize the table to new computed sizes */
  resize(L, t, nasize, nh);
}



/*
** }=============================================================
*/


Table *luaH_new (lua_State *L, int narray, int nhash) {
  Table *t = luaM_new(L, Table);
  luaC_link(L, obj2gco(t), LUA_TTABLE);
  t->metatable = NULL;
  t->flags = cast_byte(~0);
  /* temporary values (kept only if some malloc fails) */
  t->array = NULL;
  t->sizearray = 0;
  t->lsizenode = 0;
  t->node = cast(Node *, dummynode);
  t->nint = 0;
  t->nother = 0;
  t->intdirty = 0;
  t->placing = 0;
  setarrayvector(L, t, narray);
  setnodevector(L, t, nhash);
  return t;
}


void luaH_free (lua_State *L, Table *t) {
  if (t->node != dummynode)
    luaM_freemem(L, t->node, nodeblocksize(sizenode(t)));
  luaM_freearray(L, t->array, t->sizearray, TValue);
  luaM_free(L, t);
}


static Node *getfreepos (Table *t) {
  while (t->lastfree-- > t->node) {
    if (ttisnil(gkey(t->lastfree)))
      return t->lastfree;
  }
  return NULL;  /* could not find a free place */
}



/*
** inserts a new key into a hash table; first, check whether key's main 
** position is free. If not, check whether colliding node is in its main 
** position or not: if it is not, move colliding node to an empty place and 
** put new key in its main position; otherwise (colliding node is in its main 
** position), new key goes to an empty position. 
*/
static TValue *newkey (lua_State *L, Table *t, const TValue *key) {
  Node *mp;
  if (!t->placing && orderfull(t)) {  /* no free order slot? (and dummynode) */
    rehash(L, t, key, 1);  /* compact, or grow */
    return luaH_set(L, t, key);  /* re-insert key into new table */
  }
  mp = mainposition(t, key);
  if (!ttisnil(gval(mp)) || mp == dummynode) {
    Node *othern;
    Node *n = getfreepos(t);  /* get a free place */
    if (n == NULL) {  /* cannot find a free place? */
      rehash(L, t, key, 0);  /* grow table */
      return luaH_set(L, t, key);  /* re-insert key into grown table */
    }
    lua_assert(n != dummynode);
    othern = mainposition(t, key2tval(mp));
    if (othern != mp) {  /* is colliding node out of its main position? */
      /* yes; move colliding node into free position */
      while (gnext(othern) != mp) othern = gnext(othern);  /* find previous */
      gnext(othern) = n;  /* redo the chain with `n' in place of `mp' */
      *n = *mp;  /* copy colliding node into free pos. (mp->next also goes) */
      if (gord(n) >= 0) gorder(t)[gord(n)] = nodeindex(t, n);  /* its slot follows */
      gnext(mp) = NULL;  /* now `mp' is free */
      setnilvalue(gval(mp));
      gord(mp) = -1;
    }
    else {  /* colliding node is in its own main position */
      /* new node will go into free position */
      gnext(n) = gnext(mp);  /* chain new position */
      gnext(mp) = n;
      mp = n;
    }
  }
  else
    dropslot(t, mp);  /* main position is free or holds a dead key */
  gkey(mp)->value = key->value; gkey(mp)->tt = key->tt;
  if (!t->placing) appendslot(t, mp);  /* else resize gives it its slot */
  luaC_barriert(L, t, key);
  lua_assert(ttisnil(gval(mp)));
  return gval(mp);
}


/*
** search function for integers
*/
const TValue *luaH_getnum (Table *t, int key) {
  /* (1 <= key && key <= t->sizearray) */
  if (cast(unsigned int, key-1) < cast(unsigned int, t->sizearray))
    return &t->array[key-1];
  else {
    lua_Number nk = cast_num(key);
    Node *n = hashnum(t, nk);
    do {  /* check whether `key' is somewhere in the chain */
      if (ttisnumber(gkey(n)) && luai_numeq(nvalue(gkey(n)), nk))
        return gval(n);  /* that's it */
      else n = gnext(n);
    } while (n);
    return luaO_nilobject;
  }
}


/*
** search function for strings
*/
const TValue *luaH_getstr (Table *t, TString *key) {
  Node *n = hashstr(t, key);
  do {  /* check whether `key' is somewhere in the chain */
    if (ttisstring(gkey(n)) && rawtsvalue(gkey(n)) == key)
      return gval(n);  /* that's it */
    else n = gnext(n);
  } while (n);
  return luaO_nilobject;
}


/*
** main search function
*/
const TValue *luaH_get (Table *t, const TValue *key) {
  switch (ttype(key)) {
    case LUA_TNIL: return luaO_nilobject;
    case LUA_TSTRING: return luaH_getstr(t, rawtsvalue(key));
    case LUA_TNUMBER: {
      int k;
      lua_Number n = nvalue(key);
      lua_number2int(k, n);
      if (luai_numeq(cast_num(k), nvalue(key))) /* index is int? */
        return luaH_getnum(t, k);  /* use specialized version */
      /* else go through */
    }
    default: {
      Node *n = mainposition(t, key);
      do {  /* check whether `key' is somewhere in the chain */
        if (luaO_rawequalObj(key2tval(n), key))
          return gval(n);  /* that's it */
        else n = gnext(n);
      } while (n);
      return luaO_nilobject;
    }
  }
}


/*
** `p' is the value of a key that is still in the table but deleted (nil).
** A non-integer key in the hash part is being added again, so it moves to
** the end of the order; integer keys and array slots have a fixed place.
*/
static TValue *revive (lua_State *L, Table *t, TValue *p, const TValue *key) {
  Node *n;
  if (cast(size_t, p - t->array) < cast(size_t, t->sizearray) || isintkey(key))
    return p;
  n = cast(Node *, p);  /* `i_val' is a Node's first field */
  if (gord(n) >= 0 && gord(n) == t->nother - 1)
    return p;  /* already the last one */
  if (orderfull(t)) {
    rehash(L, t, key, 1);  /* drops `key', which is dead */
    return luaH_set(L, t, key);
  }
  dropslot(t, n);
  appendslot(t, n);
  return p;
}


TValue *luaH_set (lua_State *L, Table *t, const TValue *key) {
  const TValue *p = luaH_get(t, key);
  t->flags = 0;
  if (p != luaO_nilobject)
    return ttisnil(p) ? revive(L, t, cast(TValue *, p), key) : cast(TValue *, p);
  else {
    if (ttisnil(key)) luaG_runerror(L, "table index is nil");
    else if (ttisnumber(key) && luai_numisnan(nvalue(key)))
      luaG_runerror(L, "table index is NaN");
    return newkey(L, t, key);
  }
}


TValue *luaH_setnum (lua_State *L, Table *t, int key) {
  const TValue *p = luaH_getnum(t, key);
  if (p != luaO_nilobject)
    return cast(TValue *, p);
  else {
    TValue k;
    setnvalue(&k, cast_num(key));
    return newkey(L, t, &k);
  }
}


TValue *luaH_setstr (lua_State *L, Table *t, TString *key) {
  const TValue *p = luaH_getstr(t, key);
  TValue k;
  setsvalue(L, &k, key);
  if (p != luaO_nilobject)
    return ttisnil(p) ? revive(L, t, cast(TValue *, p), &k) : cast(TValue *, p);
  else
    return newkey(L, t, &k);
}


static int unbound_search (Table *t, unsigned int j) {
  unsigned int i = j;  /* i is zero or a present index */
  j++;
  /* find `i' and `j' such that i is present and j is not */
  while (!ttisnil(luaH_getnum(t, j))) {
    i = j;
    j *= 2;
    if (j > cast(unsigned int, MAX_INT)) {  /* overflow? */
      /* table was built with bad purposes: resort to linear search */
      i = 1;
      while (!ttisnil(luaH_getnum(t, i))) i++;
      return i - 1;
    }
  }
  /* now do a binary search between them */
  while (j - i > 1) {
    unsigned int m = (i+j)/2;
    if (ttisnil(luaH_getnum(t, m))) j = m;
    else i = m;
  }
  return i;
}


/*
** Try to find a boundary in table `t'. A `boundary' is an integer index
** such that t[i] is non-nil and t[i+1] is nil (and 0 if t[1] is nil).
*/
int luaH_getn (Table *t) {
  unsigned int j = t->sizearray;
  if (j > 0 && ttisnil(&t->array[j - 1])) {
    /* there is a boundary in the array part: (binary) search for it */
    unsigned int i = 0;
    while (j - i > 1) {
      unsigned int m = (i+j)/2;
      if (ttisnil(&t->array[m - 1])) j = m;
      else i = m;
    }
    return i;
  }
  /* else must find a boundary in hash part */
  else if (t->node == dummynode)  /* hash part is empty? */
    return j;  /* that is easy... */
  else return unbound_search(t, j);
}



#if defined(LUA_DEBUG)

Node *luaH_mainposition (const Table *t, const TValue *key) {
  return mainposition(t, key);
}

int luaH_isdummy (Node *n) { return n == dummynode; }

#endif
