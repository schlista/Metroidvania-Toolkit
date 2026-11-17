local Return = require "mvtk.player.hazard_return"
return {id="hazard_return", order=10,
    messages={mvtk_hazard_contact="body", mvtk_return_point="body"},
    init=Return.init, on_message=Return.on_message, pre_physics=Return.pre_physics, reset=Return.reset}
