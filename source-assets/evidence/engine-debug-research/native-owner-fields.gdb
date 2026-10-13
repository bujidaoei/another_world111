# Execute only after selecting the real _render_list_template caller frame.
# All set operations below assign debugger convenience variables, not engine data.
set $aw_surface = surf
set $aw_owner = surf->owner
set $aw_base = surf->owner->data->base._id
print /x $aw_surface
print /x $aw_owner
print /x $aw_owner->data
print /x $aw_owner->base_flags
print $aw_owner->data->base_type
print /x $aw_owner->data->base._id
print /x $aw_owner->data->skeleton._id
print /x $aw_owner->mesh_instance._id
print /x $aw_owner->transforms_uniform_set._id
print $aw_owner->instance_count
print $aw_owner->trail_steps
print /x $aw_owner->surface_caches
print /x $aw_surface->next
print /x $aw_surface->flags
info args
info locals
