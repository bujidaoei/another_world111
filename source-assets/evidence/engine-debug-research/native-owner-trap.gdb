# Prepared diagnosis only. Not executed: the portable GDB/build do not yet exist.
# Start GDB from the unique raw-evidence directory so this log stays there.
set pagination off
set print pretty on
set print elements 100
set logging file native-owner-trap.log
set logging overwrite on
set logging redirect off
set logging enabled on
set breakpoint pending off
break servers/rendering/renderer_rd/storage_rd/particles_storage.cpp:759 if particles == 0
commands
silent
echo AW_NATIVE_PARTICLES_OWNER_NULL\n
info threads
bt full
print /x p_particles._id
print particles
print /x this
# Stop here. Select the actual RenderForwardMobile::_render_list_template frame
# from the backtrace and source native-owner-fields.gdb before continuing.
end
