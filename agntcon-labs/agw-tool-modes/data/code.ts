const sum = await get_sum({a: 3, b: 4});
const echoed = await echo({message: sum});

({
  result: echoed
})
