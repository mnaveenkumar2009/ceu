local function asr_name (e, cnds, err_msg)
    ASR(e.dcl.tag~='Val', e, 'invalid '..err_msg..' : expected name expression')
    local ok do
        for _, tag in ipairs(cnds) do
            if tag == e.dcl.tag then
                ok = true
                break
            end
        end
    end
    ASR(ok, e, err_msg..' : '..
                'unexpected context for '..AST.tag2id[e.dcl.tag]
                                         ..' "'..e.dcl.id..'"')
end

local function asr_if_name (e, cnds, err_msg)
    if e.dcl.tag == 'Val' then
        return
    else
        return asr_name(e, cnds, err_msg)
    end
end

-------------------------------------------------------------------------------
-- NAMES
-------------------------------------------------------------------------------

F = {
-- OPTION: !

    ['Exp_!'] = function (me)
        local op,e = unpack(me)

        -- ctx
        asr_name(e, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.check(e.dcl[1],'?'), me,
            'invalid operand to `'..op..'´ : expected option type')

        -- dcl
        me.dcl = AST.copy(e.dcl)
        me.dcl[1] = TYPES.pop(me.dcl[1])
    end,

    ['Exp_1*'] = function (me)
        local _,ptr = unpack(me)
        if not ptr.dcl then return end

        me.dcl = AST.copy(ptr.dcl)
        if not TYPES.is_nat(me.dcl[1]) then
            me.dcl[1] = TYPES.pop(me.dcl[1])
        end
    end,

    ['Exp_$'] = function (me)
        local _, e = unpack(me)
        if not e.dcl then return end

        me.dcl = AST.copy(e.dcl)
        me.dcl.tag = 'Var'
    end,

    ['Exp_idx'] = function (me)
        local _,vec = unpack(me)
        if not vec.dcl then return end

        me.dcl = AST.copy(vec.dcl)
        if me.dcl.tag == 'Vec' then
            me.dcl.tag = 'Var'
        elseif not TYPES.is_nat(me.dcl[1]) then
            me.dcl[1] = TYPES.pop(me.dcl[1])
        end
    end,

    ['Exp_.'] = function (me)
        local _, e, member = unpack(me)
        if not e.dcl then return end

        local Type = unpack(e.dcl)
        local ID_abs, mod = unpack(Type)
        if ID_abs.dcl.tag == 'Data' then
            -- data.member
            local blk = AST.asr(ID_abs.dcl,'Data', 3,'Block')
            me.dcl = DCLS.asr(me,blk,member,false,e.dcl.id)
        else
            me.dcl = AST.copy(e.dcl)
        end
    end,

    Exp_as = function (me)
        local _,e, Type = unpack(me)
        if not e.dcl then return end

        me.dcl = AST.copy(e.dcl)
        me.dcl[1] = AST.copy(Type)
    end,
}

AST.visit(F)

-------------------------------------------------------------------------------
-- EXPS
-------------------------------------------------------------------------------

G = {
    Exp_Name = function (me)
        local e = unpack(me)
        me.dcl = AST.copy(e.dcl)
    end,

-- PRIMITIVES

    NULL = function (me)
        me.dcl = TYPES.new(me, 'null', '&&')
    end,

    NUMBER = function (me)
        local v = unpack(me)
        if math.floor(v) == tonumber(v) then
            me.dcl = TYPES.new(me, 'int')
        else
            me.dcl = TYPES.new(me, 'float')
        end
    end,

    BOOL = function (me)
        me.dcl = TYPES.new(me, 'bool')
    end,

    STRING = function (me)
        me.dcl = TYPES.new(me, '_char', '&&')
    end,

-- SIZEOF

    SIZEOF = function (me)
        local e = unpack(me)

        -- ctx
        if e.tag ~= 'Type' then
            asr_if_name(e, {'Nat','Var'}, 'invalid operand to `sizeof´')
        end

        -- tp
        -- any

        -- dcl
        me.dcl = TYPES.new(me, 'usize')
    end,

-- CALL

    Exp_Call = function (me)
        local _, e = unpack(me)

        -- ctx
        asr_name(e, {'Nat','Code'}, 'invalid call')

        -- tp
        if e.tag == 'ID_abs' then
            local id = unpack(e)
            ASR(e.dcl.tag=='Code', me,
                'invalid call : "'..id..'" is not a `code´ abstraction')
        end

        -- dcl
        if e.tag == 'ID_abs' then
            local _,_,_,_,out = unpack(e.dcl)
            me.dcl = TYPES.new(me, 'void')
            me.dcl[1] = AST.copy(out)
        else
            me.dcl = AST.copy(e.dcl)
        end
    end,

    Explist = function (me)
        for _, e in ipairs(me) do
            asr_if_name(e, {'Nat','Var'}, 'invalid argument to call')
        end
    end,

-- OPTION: ?

    ['Exp_?'] = function (me)
        local op,e = unpack(me)

        -- ctx
        asr_name(e, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.check(e.dcl[1],'?'), me,
            'invalid operand to `'..op..'´ : expected option type')

        -- dcl
        me.dcl = TYPES.new(me, 'bool')
    end,

-- VECTOR LENGTH: $, $$

    ['Exp_$$'] = 'Exp_$',
    ['Exp_$'] = function (me)
        local op,vec = unpack(me)

        -- ctx
        asr_name(vec, {'Vec'}, 'invalid operand to `'..op..'´')

        -- tp
        -- any

        -- dcl
        me.dcl = TYPES.new(me, 'usize')
    end,

-- INDEX

    ['Exp_idx'] = function (me)
        local _,vec,idx = unpack(me)

        -- ctx, tp

        local tp = AST.copy(vec.dcl[1])
        tp[2] = nil
        if (vec.dcl.tag=='Var' or vec.dcl.tag=='Nat') and TYPES.is_nat(tp) then
            -- _V[0][0]
            -- var _char&&&& argv; argv[1][0]
            -- v[1]._plain[0]
            asr_name(vec, {'Nat','Var'}, 'invalid vector')
        else
            asr_name(vec, {'Vec'}, 'invalid vector')
        end

        asr_if_name(idx, {'Nat','Var'}, 'invalid index')

        -- dcl
        me.dcl = AST.copy(vec.dcl)
        me.dcl.tag = 'Var'
        if TYPES.check(vec.dcl[1],'&&') then
            me.dcl[1] = TYPES.pop(vec.dcl[1])
        end
    end,

-- BIND

    ['Exp_1&'] = function (me)
        local op, e = unpack(me)

        -- ctx
        local par = me.__par
        ASR(par.tag=='Set_Alias' or par.tag=='Explist' or par.tag=='_Data_Explist', me,
            'invalid operand to `'..op..'´ : '..
            'unexpected context for '..AST.tag2id[e.dcl.tag]
                                     ..' "'..e.dcl.id..'"')

        -- tp

        -- dcl
        me.dcl = AST.copy(e.dcl)
        me.dcl.tag = 'Val'
    end,

-- POINTERS

    ['Exp_&&'] = function (me)
        local op, e = unpack(me)

        -- ctx
        asr_name(e, {'Nat','Var','Pool'}, 'invalid operand to `'..op..'´')

        -- tp
        -- any

        -- dcl
        me.dcl = TYPES.new(me, 'void')
        me.dcl[1] = TYPES.push(e.dcl[1],'&&')
    end,

    ['Exp_1*'] = function (me)
        local op,e = unpack(me)

        -- ctx
        asr_name(e, {'Nat','Var','Pool'}, 'invalid operand to `'..op..'´')
DBG('TODO: remove pool')

        -- tp
        local is_nat = TYPES.is_nat(e.dcl[1])
        local is_ptr = TYPES.check(e.dcl[1],'&&')
        ASR(is_nat or is_ptr, me,
            'invalid operand to `'..op..'´ : expected pointer type')

        -- dcl
        me.dcl = AST.copy(e.dcl)
        if is_ptr then
            me.dcl[1] = TYPES.pop(e.dcl[1])
        end
    end,

-- NOT

    ['Exp_not'] = function (me)
        local op, e = unpack(me)

        -- ctx
        asr_if_name(e, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.check(e.dcl[1],'bool'), me,
            'invalid operand to `'..op..'´ : expected boolean type')

        -- dcl
        me.dcl = TYPES.new(me, 'bool')
    end,

-- UNARY: +,-

    ['Exp_1+'] = 'Exp_num_num',
    ['Exp_1-'] = 'Exp_num_num',
    Exp_num_num = function (me)
        local op, e = unpack(me)

        -- ctx
        asr_if_name(e, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.is_num(e.dcl[1]), me,
            'invalid operand to `'..op..'´ : expected numeric type')

        -- dcl
        me.dcl = AST.copy(e.dcl)
        me.dcl.tag = 'Val'
    end,

-- NUMERIC: +, -, %, *, /, ^

    ['Exp_+']  = 'Exp_num_num_num',
    ['Exp_-']  = 'Exp_num_num_num',
    ['Exp_%']  = 'Exp_num_num_num',
    ['Exp_*']  = 'Exp_num_num_num',
    ['Exp_/']  = 'Exp_num_num_num',
    ['Exp_^']  = 'Exp_num_num_num',
    Exp_num_num_num = function (me)
        local op, e1, e2 = unpack(me)

        -- ctx
        asr_if_name(e1, {'Nat','Var'}, 'invalid operand to `'..op..'´')
        asr_if_name(e2, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.is_num(e1.dcl[1]) and TYPES.is_num(e2.dcl[1]), me,
            'invalid operand to `'..op..'´ : expected numeric type')

        -- dcl
        local max = TYPES.max(e1.dcl[1], e2.dcl[1])
        ASR(max, me, 'invalid operands to `'..op..'´ : '..
                        'incompatible numeric types : "'..
                        TYPES.tostring(e1.dcl[1])..'" vs "'..
                        TYPES.tostring(e2.dcl[1])..'"')
        me.dcl = TYPES.new(me,'void')
        me.dcl[1] = AST.copy(max)
    end,

-- BITWISE

    ['Exp_|']  = 'Exp_int_int_int',
    ['Exp_&']  = 'Exp_int_int_int',
    ['Exp_<<'] = 'Exp_int_int_int',
    ['Exp_>>'] = 'Exp_int_int_int',
    Exp_int_int_int = function (me)
        local op, e1, e2 = unpack(me)

        -- ctx
        asr_if_name(e1, {'Nat','Var'}, 'invalid operand to `'..op..'´')
        asr_if_name(e2, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.is_int(e1.dcl[1]) and TYPES.is_int(e2.dcl[1]), me,
            'invalid operand to `'..op..'´ : expected integer type')

        -- dcl
        local max = TYPES.max(e1.dcl[1], e2.dcl[1])
        ASR(max, me, 'invalid operands to `'..op..'´ : '..
                        'incompatible integer types : "'..
                        TYPES.tostring(e1.dcl[1])..'" vs "'..
                        TYPES.tostring(e2.dcl[1])..'"')
        me.dcl = TYPES.new(me,'void')
        me.dcl[1] = AST.copy(max)
    end,

    ['Exp_~'] = function (me)
        local op, e = unpack(me)

        -- ctx
        asr_if_name(e, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.is_int(e.dcl[1]), me,
            'invalid operand to `'..op..'´ : expected integer type')

        -- dcl
        me.dcl = AST.copy(e.dcl)
        me.dcl.tag = 'Val'
    end,

-- COMPARISON: >, >=, <, <=

    ['Exp_>='] = 'Exp_num_num_bool',
    ['Exp_<='] = 'Exp_num_num_bool',
    ['Exp_>']  = 'Exp_num_num_bool',
    ['Exp_<']  = 'Exp_num_num_bool',
    Exp_num_num_bool = function (me)
        local op, e1, e2 = unpack(me)

        -- ctx
        asr_if_name(e1, {'Nat','Var'}, 'invalid operand to `'..op..'´')
        asr_if_name(e2, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.is_num(e1.dcl[1]) and TYPES.is_num(e2.dcl[1]), me,
            'invalid operand to `'..op..'´ : expected numeric type')

        -- dcl
        me.dcl = TYPES.new(me, 'bool')
    end,

-- EQUALITY: ==, !=

    ['Exp_!='] = 'Exp_eq_bool',
    ['Exp_=='] = 'Exp_eq_bool',
    Exp_eq_bool = function (me)
        local op, e1, e2 = unpack(me)

        -- ctx
        asr_if_name(e1, {'Nat','Var'}, 'invalid operand to `'..op..'´')
        asr_if_name(e2, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.contains(e1.dcl[1],e2.dcl[1]) or
            TYPES.contains(e2.dcl[1],e1.dcl[1]), me,
            'invalid operands to `'..op..'´ : '..
            'incompatible types : "'..
                TYPES.tostring(e1.dcl[1])..'" vs "'..
                TYPES.tostring(e2.dcl[1])..'"')

        -- dcl
        me.dcl = TYPES.new(me, 'bool')
    end,

-- AND, OR

    ['Exp_or']  = 'Exp_bool_bool_bool',
    ['Exp_and'] = 'Exp_bool_bool_bool',
    Exp_bool_bool_bool = function (me)
        local op, e1, e2 = unpack(me)

        -- ctx
        asr_if_name(e1, {'Nat','Var'}, 'invalid operand to `'..op..'´')
        asr_if_name(e2, {'Nat','Var'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR(TYPES.check(e1.dcl[1],'bool') and TYPES.check(e2.dcl[1],'bool'), me,
            'invalid operand to `'..op..'´ : expected boolean type')

        -- dcl
        me.dcl = TYPES.new(me, 'bool')
    end,

-- IS, AS/CAST

    Exp_is = function (me)
        local op,e = unpack(me)

        -- ctx
        asr_if_name(e, {'Nat','Var','Pool'}, 'invalid operand to `'..op..'´')

        -- tp
        -- any

        -- dcl
        me.dcl = TYPES.new(me, 'bool')
    end,

    Exp_as = function (me)
        local op,e,Type = unpack(me)

        -- ctx
        asr_if_name(e, {'Nat','Var','Pool'}, 'invalid operand to `'..op..'´')

        -- tp
        -- any

        -- dcl
        me.dcl = AST.copy(e.dcl)
        if AST.isNode(Type) then
            me.dcl[1] = AST.copy(Type)
        else
            -- annotation (/plain, etc)
DBG'TODO: type annotation'
        end
    end,

-------------------------------------------------------------------------------

--[=[
    --------------------------------------------------------------------------

    _Data_Explist = function (me)
        for _, e in ipairs(me) do
            asr_if_name(e, {'Nat','Var'}, 'argument to constructor')
        end
    end,

    --------------------------------------------------------------------------

    Set_Exp = function (me)
        local fr, to = unpack(me)
        asr_name(to, {'Nat','Var','Pool'}, 'assignment')
        asr_if_name(fr, {'Nat','Var'}, 'assignment')
    end,

    Set_Vec = function (me)
        local fr,to = unpack(me)

        -- vec = ...
        asr_name(to, {'Vec'}, 'constructor')

        -- ... = []..vec
        if fr.tag == '_Vec_New' then
DBG'TODO: _Vec_New'
            for _, e in ipairs(fr) do
                asr_if_name(e, {'Vec'}, 'constructor')
            end
        end
    end,

    Set_Lua = function (me)
        local _,to = unpack(me)
        asr_name(to, {'Nat','Var'}, 'Lua assignment')
    end,

    Set_Data = function (me)
        local Data_New, Exp_Name = unpack(me)
        local is_new = unpack(Data_New)
        if is_new then
            -- pool = ...
            asr_name(Exp_Name, {'Var','Pool'}, 'constructor')
        else
            asr_name(Exp_Name, {'Var'}, 'constructor')
        end
    end,

    --------------------------------------------------------------------------

    _Pause    = 'Await_Evt',
    Emit_Evt  = 'Await_Evt',
    Await_Evt = function (me, tag)
        local Exp_Name = unpack(me)
        local tag do
            if me.tag == 'Await_Evt' then
                tag = 'await'
            elseif me.tag == 'Emit_Evt' then
                tag = 'emit'
            else
                assert(me.tag == '_Pause')
                tag = 'pause/if'
            end
        end
        if me.tag == 'Await_Evt' then
            asr_name(Exp_Name, {'Var','Evt','Pool'}, '`'..tag..'´')
        else
            asr_name(Exp_Name, {'Evt'}, '`'..tag..'´')
        end
    end,

    Varlist = function (me)
        local cnds = {'Nat','Var'}
        if string.sub(me.__par.tag,1,7) == '_Async_' then
            cnds[#cnds+1] = 'Vec'
        end
        for _, var in ipairs(me) do
            asr_name(var, cnds, 'variable')
        end
    end,

    Do = function (me)
        local _,_,e = unpack(me)
        if e then
            asr_name(e, {'Nat','Var'}, 'assignment')
        end
    end,
]=]
}
AST.visit(G)
