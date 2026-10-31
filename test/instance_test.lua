-- A bundle must reuse an already loaded, compatible Tarmac instead of
-- starting a second copy.

local loaded = { version = "0.1.99", marker = "standalone" }
tarmac = loaded

dcs.start(fixture.mission())
loadBundle()

test("a compatible loaded instance is reused", function()
    expect.equal(tarmac, loaded)
    expect.equal(tarmac.marker, "standalone")
    expect.equal(dcs.handlerCount(), 0, "the bundled copy must not register event handlers")
end)
