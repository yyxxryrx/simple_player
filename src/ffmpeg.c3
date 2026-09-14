module simple_player::ffmpeg;
import ffi;

faultdef CONVERT_FAILED;

<*
 transform error code to string

 @param errnum : "Error code"
 @return "error message"
 @return ? CONVERT_FAILED
*>
fn String? err2str(Allocator allocator, int errnum) {
    char[] buf = alloc::new_array(allocator, char, ffi::AV_ERROR_MAX_STRING_SIZE);
    int ret    = ffi::str_error(errnum, buf.ptr, buf.len);
    if (ret < 0) return CONVERT_FAILED~;
    buf[^1] = 0;
    return ((ZString)buf.ptr).str_view();
}
