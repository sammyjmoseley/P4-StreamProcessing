import os
import sys

sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'utils/'))

import p4runtime_lib.helper

BASE_NAME = 'MyIngress'
TABLE_NAME = '%s.stream_ops' % (BASE_NAME,)


class Command(object):
    def install(self, switch, schema, line_no):
        switch.WriteTableEntry(self._to_table_entry(schema, line_no))

    def _to_table_entry(self, schema, line_no):
        return p4info_helper.buildTableEntry(
            table_name=TABLE_NAME,
            match_fields={
                "hdr.entry[0].schema": schema,
                "meta.lineNo": line_no
            },
            action_name="MyIngress.%s" % (self._action_name(),),
            action_params=self._action_params())

    def _action_name(self):
        raise Exception('unimplemented action name')

    def _action_params(self):
        raise Exception('unimplemented action name')


class MapAdd(Command):
    def __init__(self, i):
        self.i = i

    def _action_name(self):
        return "map_add"

    def _action_params(self):
        return {
            'i': self.i
        }


class MapEq(Command):
    def __init__(self, i):
        self.i = i

    def _action_name(self):
        return "map_eq"

    def _action_params(self):
        return {
            'i': self.i
        }


class FilterEq(Command):
    def __init__(self, i):
        self.i = i

    def _action_name(self):
        return "filter_eq"

    def _action_params(self):
        return {
            'i': self.i
        }


class KeyWindowAggregate(Command):
    def __init__(self):
        pass

    def _action_name(self):
        return 'key_window_aggregate'

    def _action_params(self):
        return {}


class JoinSum(Command):
    def __init__(self):
        pass

    def _action_name(self):
        return 'join_sum'

    def _action_params(self):
        return {}


