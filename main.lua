local Task = require("Tasks")

function love.update(dt)
    Task.runTasks()
end

--- Basic functionality
--- This function will create 10 tasks to print "Hello, world" to the console.
--- This will create issues with the console output, as the tasks will run in parallel.
-- Task.wrapAsyncFunction(function()
--     local thread = Task.newTaskThread [[
--         print(...)
--     ]]

--     for i = 1, 10 do
--         Task.newTask(thread, { "Hello, world", i })
--     end
-- end)

--- Synced tasks
--- This function will create 10 tasks to print "Hello, world" to the console.
--- This won't create issue with the console output, as the tasks will run in sequence.
-- Task.wrapAsyncFunction(function()
--     local thread = Task.newTaskThread [[
--         print(...)
--     ]]

--     for i = 1, 10 do
--         Task.newSyncedTask(thread, { "Hello, world", i })
--     end
-- end)

--- Callbacks
--- This function will create 10 tasks to add 1-10 to a sum and print the sum to the console.
--- This won't work because all functions will be created with the sum value of 0.
-- Task.wrapAsyncFunction(function()
--     local thread = Task.newTaskThread [[
--         return select(1, ...) + select(2, ...)
--     ]]

--     local sum = 0

--     for i = 1, 10 do
--         Task.newTask(thread, { sum, i }, function(result)
--             sum = result
--             print(sum)
--         end)
--     end
-- end)

--- Await
--- This function will create 10 tasks to add 1-10 to a sum and print the sum to the console.
--- This will work because the sum value will be passed to the next task.
-- Task.wrapAsyncFunction(function()
--     local thread = Task.newTaskThread [[
--         return select(1, ...) + select(2, ...)
--     ]]

--     local sum = 0

--     for i = 1, 10 do
--         local task = Task.newTask(thread, { sum, i }, function(result)
--             sum = result
--             print(sum)
--         end)

--         Task.await(task)
--     end
-- end)

--- Task groups
--- Let's say you want a function to generate a noise map in parallel
--- This function will create a group of tasks to generate the noise values and await the result
Task.wrapAsyncFunction(function()
    local thread = Task.newTaskThread [[
        require("love.math")
        local index, size, data, scale = ...

        for i = index, index + size - 1 do
            local x = i % size
            local y = math.floor(index)

            local value = love.math.noise(x * scale, y * scale)

            data:setPixel(x, y, value, value, value, 1)
        end
    ]]

    local size = 500 -- size of the image

    -- noise map scale
    local scale = 0.0123 -- some random value

    -- noise values to store, amount of values times the size of a float
    local data = love.image.newImageData(size, size, "rgba8")

    local group = Task.setNewTaskGroup()

    -- n amount of threads will be started to generate n noise values each.
    for i = 0, size - 1 do
        Task.newTask(thread, { i, size, data, scale })
    end

    Task.await(group)
    -- you can also use Task.barrier(function() end) as a way to block it as well (if your add a callback and check if all items exist for example)

    -- create your pretty noise map
    local image = love.graphics.newImage(data)

    return image
end, function(result)
    -- (define a love.draw function to draw the result (don't do this in your project though :P))
    function love.draw()
        love.graphics.draw(result)
    end
end)

function love.quit()
    Task.Shutdown()
end
