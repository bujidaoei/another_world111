"""GDB-side read-only capture; never call inferior methods or write engine state."""
import gdb
import json
import time

observations = []
def evaluate(expression):
    try:
        value = gdb.parse_and_eval(expression)
        try:
            return {'expression': expression, 'value': str(value), 'integer': int(value)}
        except (ValueError, TypeError, gdb.error):
            return {'expression': expression, 'value': str(value)}
    except gdb.error as error:
        return {'expression': expression, 'error': str(error)}

class NullParticlesOwner(gdb.Breakpoint):
    def __init__(self):
        super().__init__('servers/rendering/renderer_rd/storage_rd/particles_storage.cpp:759')
        self.condition = 'particles == 0'
    def stop(self):
        print('AW_NATIVE_PARTICLES_OWNER_NULL', flush=True)
        record = {'wall_time': time.time(), 'thread': gdb.selected_thread().global_num,
                  'particles_fields': [evaluate(x) for x in ['p_particles._id', 'particles', '(uintptr_t)this', 'this->particles_owner.alloc.max_alloc', 'this->particles_owner.alloc.elements_in_chunk']]}
        for command in ['info threads', 'bt full']:
            try:
                print(gdb.execute(command, to_string=True), flush=True)
            except gdb.error as error:
                print('AW_GDB_COMMAND_ERROR', command, str(error), flush=True)
        original = gdb.selected_frame()
        frame = original.older()
        while frame:
            frame.select()
            name = frame.name() or ''
            if '_render_list' in name:
                try:
                    frame.read_var('surf')
                except gdb.error:
                    frame = frame.older()
                    continue
                record['draw_frame'] = name
                record['geometry_fields'] = [evaluate(x) for x in [
                    '(uintptr_t)surf', '(uintptr_t)surf->owner', '(uintptr_t)surf->owner->data',
                    'surf->owner->base_flags', 'surf->owner->data->base_type',
                    'surf->owner->data->base._id', 'surf->owner->data->skeleton._id',
                    'surf->owner->mesh_instance._id', 'surf->owner->transforms_uniform_set._id',
                    'surf->owner->instance_count', 'surf->owner->trail_steps',
                    '(uintptr_t)surf->owner->surface_caches', '(uintptr_t)surf->next',
                    'surf->flags', 'surf->surface_index', '(uintptr_t)surf->surface',
                    'p_params->pass_mode', 'p_params->element_count', 'p_from_element', 'p_to_element']]
                print('AW_NATIVE_OWNER_FIELDS', json.dumps(record), flush=True)
                break
            frame = frame.older()
        original.select()
        observations.append(record)
        with open('native-owner-observations.json', 'w', encoding='utf-8') as stream:
            json.dump(observations, stream, indent=2)
        # Diagnostic captures resume the unmodified error path and normal QA/quit.
        return False

breakpoint = NullParticlesOwner()
print('AW_READ_ONLY_CAPTURE_INSTALLED', flush=True)
