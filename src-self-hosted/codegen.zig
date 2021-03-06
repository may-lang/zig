const std = @import("std");
const builtin = @import("builtin");
const Compilation = @import("compilation.zig").Compilation;
const llvm = @import("llvm.zig");
const c = @import("c.zig");
const ir = @import("ir.zig");
const Value = @import("value.zig").Value;
const Type = @import("type.zig").Type;
const Scope = @import("scope.zig").Scope;
const event = std.event;
const assert = std.debug.assert;
const DW = std.dwarf;

pub async fn renderToLlvm(comp: *Compilation, fn_val: *Value.Fn, code: *ir.Code) !void {
    fn_val.base.ref();
    defer fn_val.base.deref(comp);
    defer code.destroy(comp.gpa());

    var output_path = try await (async comp.createRandomOutputPath(comp.target.objFileExt()) catch unreachable);
    errdefer output_path.deinit();

    const llvm_handle = try comp.event_loop_local.getAnyLlvmContext();
    defer llvm_handle.release(comp.event_loop_local);

    const context = llvm_handle.node.data;

    const module = llvm.ModuleCreateWithNameInContext(comp.name.ptr(), context) orelse return error.OutOfMemory;
    defer llvm.DisposeModule(module);

    llvm.SetTarget(module, comp.llvm_triple.ptr());
    llvm.SetDataLayout(module, comp.target_layout_str);

    if (comp.target.getObjectFormat() == builtin.ObjectFormat.coff) {
        llvm.AddModuleCodeViewFlag(module);
    } else {
        llvm.AddModuleDebugInfoFlag(module);
    }

    const builder = llvm.CreateBuilderInContext(context) orelse return error.OutOfMemory;
    defer llvm.DisposeBuilder(builder);

    const dibuilder = llvm.CreateDIBuilder(module, true) orelse return error.OutOfMemory;
    defer llvm.DisposeDIBuilder(dibuilder);

    // Don't use ZIG_VERSION_STRING here. LLVM misparses it when it includes
    // the git revision.
    const producer = try std.Buffer.allocPrint(
        &code.arena.allocator,
        "zig {}.{}.{}",
        u32(c.ZIG_VERSION_MAJOR),
        u32(c.ZIG_VERSION_MINOR),
        u32(c.ZIG_VERSION_PATCH),
    );
    const flags = c"";
    const runtime_version = 0;
    const compile_unit_file = llvm.CreateFile(
        dibuilder,
        comp.name.ptr(),
        comp.root_package.root_src_dir.ptr(),
    ) orelse return error.OutOfMemory;
    const is_optimized = comp.build_mode != builtin.Mode.Debug;
    const compile_unit = llvm.CreateCompileUnit(
        dibuilder,
        DW.LANG_C99,
        compile_unit_file,
        producer.ptr(),
        is_optimized,
        flags,
        runtime_version,
        c"",
        0,
        !comp.strip,
    ) orelse return error.OutOfMemory;

    var ofile = ObjectFile{
        .comp = comp,
        .module = module,
        .builder = builder,
        .dibuilder = dibuilder,
        .context = context,
        .lock = event.Lock.init(comp.loop),
        .arena = &code.arena.allocator,
    };

    try renderToLlvmModule(&ofile, fn_val, code);

    // TODO module level assembly
    //if (buf_len(&g->global_asm) != 0) {
    //    LLVMSetModuleInlineAsm(g->module, buf_ptr(&g->global_asm));
    //}

    llvm.DIBuilderFinalize(dibuilder);

    if (comp.verbose_llvm_ir) {
        std.debug.warn("raw module:\n");
        llvm.DumpModule(ofile.module);
    }

    // verify the llvm module when safety is on
    if (std.debug.runtime_safety) {
        var error_ptr: ?[*]u8 = null;
        _ = llvm.VerifyModule(ofile.module, llvm.AbortProcessAction, &error_ptr);
    }

    assert(comp.emit_file_type == Compilation.Emit.Binary); // TODO support other types

    const is_small = comp.build_mode == builtin.Mode.ReleaseSmall;
    const is_debug = comp.build_mode == builtin.Mode.Debug;

    var err_msg: [*]u8 = undefined;
    // TODO integrate this with evented I/O
    if (llvm.TargetMachineEmitToFile(
        comp.target_machine,
        module,
        output_path.ptr(),
        llvm.EmitBinary,
        &err_msg,
        is_debug,
        is_small,
    )) {
        if (std.debug.runtime_safety) {
            std.debug.panic("unable to write object file {}: {s}\n", output_path.toSliceConst(), err_msg);
        }
        return error.WritingObjectFileFailed;
    }
    //validate_inline_fns(g); TODO
    fn_val.containing_object = output_path;
    if (comp.verbose_llvm_ir) {
        std.debug.warn("optimized module:\n");
        llvm.DumpModule(ofile.module);
    }
    if (comp.verbose_link) {
        std.debug.warn("created {}\n", output_path.toSliceConst());
    }
}

pub const ObjectFile = struct {
    comp: *Compilation,
    module: llvm.ModuleRef,
    builder: llvm.BuilderRef,
    dibuilder: *llvm.DIBuilder,
    context: llvm.ContextRef,
    lock: event.Lock,
    arena: *std.mem.Allocator,

    fn gpa(self: *ObjectFile) *std.mem.Allocator {
        return self.comp.gpa();
    }
};

pub fn renderToLlvmModule(ofile: *ObjectFile, fn_val: *Value.Fn, code: *ir.Code) !void {
    // TODO audit more of codegen.cpp:fn_llvm_value and port more logic
    const llvm_fn_type = try fn_val.base.typ.getLlvmType(ofile.arena, ofile.context);
    const llvm_fn = llvm.AddFunction(
        ofile.module,
        fn_val.symbol_name.ptr(),
        llvm_fn_type,
    ) orelse return error.OutOfMemory;

    const want_fn_safety = fn_val.block_scope.?.safety.get(ofile.comp);
    if (want_fn_safety and ofile.comp.haveLibC()) {
        try addLLVMFnAttr(ofile, llvm_fn, "sspstrong");
        try addLLVMFnAttrStr(ofile, llvm_fn, "stack-protector-buffer-size", "4");
    }

    // TODO
    //if (fn_val.align_stack) |align_stack| {
    //    try addLLVMFnAttrInt(ofile, llvm_fn, "alignstack", align_stack);
    //}

    const fn_type = fn_val.base.typ.cast(Type.Fn).?;
    const fn_type_normal = &fn_type.key.data.Normal;

    try addLLVMFnAttr(ofile, llvm_fn, "nounwind");
    //add_uwtable_attr(g, fn_table_entry->llvm_value);
    try addLLVMFnAttr(ofile, llvm_fn, "nobuiltin");

    //if (g->build_mode == BuildModeDebug && fn_table_entry->fn_inline != FnInlineAlways) {
    //    ZigLLVMAddFunctionAttr(fn_table_entry->llvm_value, "no-frame-pointer-elim", "true");
    //    ZigLLVMAddFunctionAttr(fn_table_entry->llvm_value, "no-frame-pointer-elim-non-leaf", nullptr);
    //}

    //if (fn_table_entry->section_name) {
    //    LLVMSetSection(fn_table_entry->llvm_value, buf_ptr(fn_table_entry->section_name));
    //}
    //if (fn_table_entry->align_bytes > 0) {
    //    LLVMSetAlignment(fn_table_entry->llvm_value, (unsigned)fn_table_entry->align_bytes);
    //} else {
    //    // We'd like to set the best alignment for the function here, but on Darwin LLVM gives
    //    // "Cannot getTypeInfo() on a type that is unsized!" assertion failure when calling
    //    // any of the functions for getting alignment. Not specifying the alignment should
    //    // use the ABI alignment, which is fine.
    //}

    //if (!type_has_bits(return_type)) {
    //    // nothing to do
    //} else if (type_is_codegen_pointer(return_type)) {
    //    addLLVMAttr(fn_table_entry->llvm_value, 0, "nonnull");
    //} else if (handle_is_ptr(return_type) &&
    //        calling_convention_does_first_arg_return(fn_type->data.fn.fn_type_id.cc))
    //{
    //    addLLVMArgAttr(fn_table_entry->llvm_value, 0, "sret");
    //    addLLVMArgAttr(fn_table_entry->llvm_value, 0, "nonnull");
    //}

    // TODO set parameter attributes

    // TODO
    //uint32_t err_ret_trace_arg_index = get_err_ret_trace_arg_index(g, fn_table_entry);
    //if (err_ret_trace_arg_index != UINT32_MAX) {
    //    addLLVMArgAttr(fn_table_entry->llvm_value, (unsigned)err_ret_trace_arg_index, "nonnull");
    //}

    const cur_ret_ptr = if (fn_type_normal.return_type.handleIsPtr()) llvm.GetParam(llvm_fn, 0) else null;

    // build all basic blocks
    for (code.basic_block_list.toSlice()) |bb| {
        bb.llvm_block = llvm.AppendBasicBlockInContext(
            ofile.context,
            llvm_fn,
            bb.name_hint,
        ) orelse return error.OutOfMemory;
    }
    const entry_bb = code.basic_block_list.at(0);
    llvm.PositionBuilderAtEnd(ofile.builder, entry_bb.llvm_block);

    llvm.ClearCurrentDebugLocation(ofile.builder);

    // TODO set up error return tracing
    // TODO allocate temporary stack values

    const var_list = fn_type.non_key.Normal.variable_list.toSliceConst();
    // create debug variable declarations for variables and allocate all local variables
    for (var_list) |var_scope, i| {
        const var_type = switch (var_scope.data) {
            Scope.Var.Data.Const => unreachable,
            Scope.Var.Data.Param => |param| param.typ,
        };
        //    if (!type_has_bits(var->value->type)) {
        //        continue;
        //    }
        //    if (ir_get_var_is_comptime(var))
        //        continue;
        //    if (type_requires_comptime(var->value->type))
        //        continue;
        //    if (var->src_arg_index == SIZE_MAX) {
        //        var->value_ref = build_alloca(g, var->value->type, buf_ptr(&var->name), var->align_bytes);

        //        var->di_loc_var = ZigLLVMCreateAutoVariable(g->dbuilder, get_di_scope(g, var->parent_scope),
        //                buf_ptr(&var->name), import->di_file, (unsigned)(var->decl_node->line + 1),
        //                var->value->type->di_type, !g->strip_debug_symbols, 0);

        //    } else {
        // it's a parameter
        //        assert(var->gen_arg_index != SIZE_MAX);
        //        TypeTableEntry *gen_type;
        //        FnGenParamInfo *gen_info = &fn_table_entry->type_entry->data.fn.gen_param_info[var->src_arg_index];

        if (var_type.handleIsPtr()) {
            //            if (gen_info->is_byval) {
            //                gen_type = var->value->type;
            //            } else {
            //                gen_type = gen_info->type;
            //            }
            var_scope.data.Param.llvm_value = llvm.GetParam(llvm_fn, @intCast(c_uint, i));
        } else {
            //            gen_type = var->value->type;
            var_scope.data.Param.llvm_value = try renderAlloca(ofile, var_type, var_scope.name, Type.Pointer.Align.Abi);
        }
        //        if (var->decl_node) {
        //            var->di_loc_var = ZigLLVMCreateParameterVariable(g->dbuilder, get_di_scope(g, var->parent_scope),
        //                    buf_ptr(&var->name), import->di_file,
        //                    (unsigned)(var->decl_node->line + 1),
        //                    gen_type->di_type, !g->strip_debug_symbols, 0, (unsigned)(var->gen_arg_index + 1));
        //        }

        //    }
    }

    // TODO finishing error return trace setup. we have to do this after all the allocas.

    // create debug variable declarations for parameters
    // rely on the first variables in the variable_list being parameters.
    //size_t next_var_i = 0;
    for (fn_type.key.data.Normal.params) |param, i| {
        //FnGenParamInfo *info = &fn_table_entry->type_entry->data.fn.gen_param_info[param_i];
        //if (info->gen_index == SIZE_MAX)
        //    continue;
        const scope_var = var_list[i];
        //assert(variable->src_arg_index != SIZE_MAX);
        //next_var_i += 1;
        //assert(variable);
        //assert(variable->value_ref);

        if (!param.typ.handleIsPtr()) {
            //clear_debug_source_node(g);
            const llvm_param = llvm.GetParam(llvm_fn, @intCast(c_uint, i));
            _ = renderStoreUntyped(
                ofile,
                llvm_param,
                scope_var.data.Param.llvm_value,
                Type.Pointer.Align.Abi,
                Type.Pointer.Vol.Non,
            );
        }

        //if (variable->decl_node) {
        //    gen_var_debug_decl(g, variable);
        //}
    }

    for (code.basic_block_list.toSlice()) |current_block| {
        llvm.PositionBuilderAtEnd(ofile.builder, current_block.llvm_block);
        for (current_block.instruction_list.toSlice()) |instruction| {
            if (instruction.ref_count == 0 and !instruction.hasSideEffects()) continue;

            instruction.llvm_value = try instruction.render(ofile, fn_val);
        }
        current_block.llvm_exit_block = llvm.GetInsertBlock(ofile.builder);
    }
}

fn addLLVMAttr(
    ofile: *ObjectFile,
    val: llvm.ValueRef,
    attr_index: llvm.AttributeIndex,
    attr_name: []const u8,
) !void {
    const kind_id = llvm.GetEnumAttributeKindForName(attr_name.ptr, attr_name.len);
    assert(kind_id != 0);
    const llvm_attr = llvm.CreateEnumAttribute(ofile.context, kind_id, 0) orelse return error.OutOfMemory;
    llvm.AddAttributeAtIndex(val, attr_index, llvm_attr);
}

fn addLLVMAttrStr(
    ofile: *ObjectFile,
    val: llvm.ValueRef,
    attr_index: llvm.AttributeIndex,
    attr_name: []const u8,
    attr_val: []const u8,
) !void {
    const llvm_attr = llvm.CreateStringAttribute(
        ofile.context,
        attr_name.ptr,
        @intCast(c_uint, attr_name.len),
        attr_val.ptr,
        @intCast(c_uint, attr_val.len),
    ) orelse return error.OutOfMemory;
    llvm.AddAttributeAtIndex(val, attr_index, llvm_attr);
}

fn addLLVMAttrInt(
    val: llvm.ValueRef,
    attr_index: llvm.AttributeIndex,
    attr_name: []const u8,
    attr_val: u64,
) !void {
    const kind_id = llvm.GetEnumAttributeKindForName(attr_name.ptr, attr_name.len);
    assert(kind_id != 0);
    const llvm_attr = llvm.CreateEnumAttribute(ofile.context, kind_id, attr_val) orelse return error.OutOfMemory;
    llvm.AddAttributeAtIndex(val, attr_index, llvm_attr);
}

fn addLLVMFnAttr(ofile: *ObjectFile, fn_val: llvm.ValueRef, attr_name: []const u8) !void {
    return addLLVMAttr(ofile, fn_val, @maxValue(llvm.AttributeIndex), attr_name);
}

fn addLLVMFnAttrStr(ofile: *ObjectFile, fn_val: llvm.ValueRef, attr_name: []const u8, attr_val: []const u8) !void {
    return addLLVMAttrStr(ofile, fn_val, @maxValue(llvm.AttributeIndex), attr_name, attr_val);
}

fn addLLVMFnAttrInt(ofile: *ObjectFile, fn_val: llvm.ValueRef, attr_name: []const u8, attr_val: u64) !void {
    return addLLVMAttrInt(ofile, fn_val, @maxValue(llvm.AttributeIndex), attr_name, attr_val);
}

fn renderLoadUntyped(
    ofile: *ObjectFile,
    ptr: llvm.ValueRef,
    alignment: Type.Pointer.Align,
    vol: Type.Pointer.Vol,
    name: [*]const u8,
) !llvm.ValueRef {
    const result = llvm.BuildLoad(ofile.builder, ptr, name) orelse return error.OutOfMemory;
    switch (vol) {
        Type.Pointer.Vol.Non => {},
        Type.Pointer.Vol.Volatile => llvm.SetVolatile(result, 1),
    }
    llvm.SetAlignment(result, resolveAlign(ofile, alignment, llvm.GetElementType(llvm.TypeOf(ptr))));
    return result;
}

fn renderLoad(ofile: *ObjectFile, ptr: llvm.ValueRef, ptr_type: *Type.Pointer, name: [*]const u8) !llvm.ValueRef {
    return renderLoadUntyped(ofile, ptr, ptr_type.key.alignment, ptr_type.key.vol, name);
}

pub fn getHandleValue(ofile: *ObjectFile, ptr: llvm.ValueRef, ptr_type: *Type.Pointer) !?llvm.ValueRef {
    const child_type = ptr_type.key.child_type;
    if (!child_type.hasBits()) {
        return null;
    }
    if (child_type.handleIsPtr()) {
        return ptr;
    }
    return try renderLoad(ofile, ptr, ptr_type, c"");
}

pub fn renderStoreUntyped(
    ofile: *ObjectFile,
    value: llvm.ValueRef,
    ptr: llvm.ValueRef,
    alignment: Type.Pointer.Align,
    vol: Type.Pointer.Vol,
) !llvm.ValueRef {
    const result = llvm.BuildStore(ofile.builder, value, ptr) orelse return error.OutOfMemory;
    switch (vol) {
        Type.Pointer.Vol.Non => {},
        Type.Pointer.Vol.Volatile => llvm.SetVolatile(result, 1),
    }
    llvm.SetAlignment(result, resolveAlign(ofile, alignment, llvm.TypeOf(value)));
    return result;
}

pub fn renderStore(
    ofile: *ObjectFile,
    value: llvm.ValueRef,
    ptr: llvm.ValueRef,
    ptr_type: *Type.Pointer,
) !llvm.ValueRef {
    return renderStoreUntyped(ofile, value, ptr, ptr_type.key.alignment, ptr_type.key.vol);
}

pub fn renderAlloca(
    ofile: *ObjectFile,
    var_type: *Type,
    name: []const u8,
    alignment: Type.Pointer.Align,
) !llvm.ValueRef {
    const llvm_var_type = try var_type.getLlvmType(ofile.arena, ofile.context);
    const name_with_null = try std.cstr.addNullByte(ofile.arena, name);
    const result = llvm.BuildAlloca(ofile.builder, llvm_var_type, name_with_null.ptr) orelse return error.OutOfMemory;
    llvm.SetAlignment(result, resolveAlign(ofile, alignment, llvm_var_type));
    return result;
}

pub fn resolveAlign(ofile: *ObjectFile, alignment: Type.Pointer.Align, llvm_type: llvm.TypeRef) u32 {
    return switch (alignment) {
        Type.Pointer.Align.Abi => return llvm.ABIAlignmentOfType(ofile.comp.target_data_ref, llvm_type),
        Type.Pointer.Align.Override => |a| a,
    };
}
