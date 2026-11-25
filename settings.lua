-- Owner settings page: /whip -> Config -> Cinematic Director.
-- Each key is a path into Config; config.lua's value is the default, and an admin's change is
-- written back into Config on both sides, so the rest of the resource reads it as usual.

Whip.configPage({
    label = 'Cinematic Director (whip_cine)',
    groups = {
        { label = 'Projects', settings = {
            { key = 'Storage.MaxProjects', type = 'int', min = 1, max = 200, label = 'Projects per character' },
            { key = 'Storage.AutosaveSec', type = 'int', min = 0, max = 1800, unit = 's', label = 'Autosave every (0 = off)' },
        } },
        { label = 'Stage', settings = {
            { key = 'Actors.Max', type = 'int', min = 1, max = 40, label = 'Actors per project' },
            { key = 'Lights.Max', type = 'int', min = 1, max = 64, label = 'Lights per project' },
        } },
        { label = 'Session', settings = {
            { key = 'Session.HidePlayer',   type = 'bool', label = 'Hide the filming player (on their own screen)' },
            { key = 'Session.FreezePlayer', type = 'bool', label = 'Freeze and protect the filming player' },
            { key = 'Session.CloseOnDeath', type = 'bool', label = 'Close the director when the player dies' },
            { key = 'RockstarEditor.Enabled', type = 'bool', label = 'Allow Rockstar Editor recording' },
            { key = 'Dof.Enabled', type = 'bool', label = 'Depth of field (turn off when using ReShade DOF)' },
        } },
    },
})
