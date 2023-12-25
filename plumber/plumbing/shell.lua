plumber.write("$ ")
while true do
  coroutine.yield()
  plumber.write(plumber.waitInput(1), "$ ")
end
