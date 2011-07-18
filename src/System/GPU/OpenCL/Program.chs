-- -----------------------------------------------------------------------------
-- This file is part of Haskell-Opencl.

-- Haskell-Opencl is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- Haskell-Opencl is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with Haskell-Opencl.  If not, see <http://www.gnu.org/licenses/>.
-- -----------------------------------------------------------------------------
{-# LANGUAGE ForeignFunctionInterface, ScopedTypeVariables #-}
module System.GPU.OpenCL.Program(  
  -- * Types
  CLProgram, CLBuildStatus(..),
  -- * Functions
  clCreateProgramWithSource, clRetainProgram, clReleaseProgram, 
  clUnloadCompiler, clBuildProgram, clGetProgramReferenceCount, 
  clGetProgramContext, clGetProgramNumDevices, clGetProgramDevices,
  clGetProgramSource, clGetProgramBinarySizes, clGetProgramBinaries, 
  clGetProgramBuildStatus, clGetProgramBuildOptions, clGetProgramBuildLog
  ) where

-- -----------------------------------------------------------------------------
import Foreign
import Foreign.C.Types
import Foreign.C.String( CString, withCString, newCString, peekCString )
import System.GPU.OpenCL.Types( 
  CLint, CLuint, CLProgram, CLContext, CLDeviceID, CLError(..), CLProgramInfo_,
  CLBuildStatus(..), CLBuildStatus_, wrapCheckSuccess, wrapPError, wrapGetInfo, 
  getCLValue, getEnumCL )

#include <CL/cl.h>

-- -----------------------------------------------------------------------------
type BuildCallback = CLProgram -> Ptr () -> IO ()
foreign import ccall "clCreateProgramWithSource" raw_clCreateProgramWithSource :: 
  CLContext -> CLuint -> Ptr CString -> Ptr CSize -> Ptr CLint -> IO CLProgram
--foreign import ccall "clCreateProgramWithBinary" raw_clCreateProgramWithBinary :: 
--  CLContext -> CLuint -> Ptr CLDeviceID -> Ptr CSize -> Ptr (Ptr Word8) -> Ptr CLint -> Ptr CLint -> IO CLProgram
foreign import ccall "clRetainProgram" raw_clRetainProgram :: 
  CLProgram -> IO CLint
foreign import ccall "clReleaseProgram" raw_clReleaseProgram :: 
  CLProgram -> IO CLint
foreign import ccall "clBuildProgram" raw_clBuildProgram :: 
  CLProgram -> CLuint -> Ptr CLDeviceID -> CString -> FunPtr BuildCallback -> Ptr () -> IO CLint
foreign import ccall "clUnloadCompiler" raw_clUnloadCompiler :: 
  IO CLint
foreign import ccall "clGetProgramInfo" raw_clGetProgramInfo :: 
  CLProgram -> CLuint -> CSize -> Ptr () -> Ptr CSize -> IO CLint
foreign import ccall "clGetProgramBuildInfo"  raw_clGetProgramBuildInfo :: 
  CLProgram -> CLDeviceID -> CLuint -> CSize -> Ptr () -> Ptr CSize -> IO CLint

-- -----------------------------------------------------------------------------
{-| Creates a program object for a context, and loads the source code specified
by the text strings in the strings array into the program object. The devices
associated with the program object are the devices associated with context.

OpenCL allows applications to create a program object using the program source
or binary and build appropriate program executables. This allows applications to
determine whether they want to use the pre-built offline binary or load and
compile the program source and use the executable compiled/linked online as the
program executable. This can be very useful as it allows applications to load
and build program executables online on its first instance for appropriate
OpenCL devices in the system. These executables can now be queried and cached by
the application. Future instances of the application launching will no longer
need to compile and build the program executables. The cached executables can be
read and loaded by the application, which can help significantly reduce the
application initialization time.

An OpenCL program consists of a set of kernels that are identified as functions
declared with the __kernel qualifier in the program source. OpenCL programs may
also contain auxiliary functions and constant data that can be used by __kernel
functions. The program executable can be generated online or offline by the
OpenCL compiler for the appropriate target device(s).

'clCreateProgramWithSource' returns a valid non-zero program object if the
program object is created successfully. Otherwise, it returns one of the
following error values:

 * 'CL_INVALID_CONTEXT' if context is not a valid context.

 * 'CL_OUT_OF_HOST_MEMORY' if there is a failure to allocate resources required
by the OpenCL implementation on the host.  
-}
clCreateProgramWithSource :: CLContext -> String -> IO (Either CLError CLProgram)
clCreateProgramWithSource ctx source = wrapPError $ \perr -> do
  let strings = lines source
      count = fromIntegral $ length strings
  cstrings <- mapM newCString strings
  prog <- withArray cstrings $ \srcArray -> do
    raw_clCreateProgramWithSource ctx count srcArray nullPtr perr
  mapM_ free cstrings
  return prog
  
-- | Increments the program reference count. 'clRetainProgram' returns 'True' if 
-- the function is executed successfully. It returns 'False' if program is not a 
-- valid program object.
clRetainProgram :: CLProgram -> IO Bool
clRetainProgram prg = wrapCheckSuccess $ raw_clRetainProgram prg

-- | Decrements the program reference count. The program object is deleted after 
-- all kernel objects associated with program have been deleted and the program 
-- reference count becomes zero. 'clReleseProgram' returns 'True' if 
-- the function is executed successfully. It returns 'False' if program is not a 
-- valid program object.
clReleaseProgram :: CLProgram -> IO Bool
clReleaseProgram prg = wrapCheckSuccess $ raw_clReleaseProgram prg

-- | Allows the implementation to release the resources allocated by the OpenCL
-- compiler. This is a hint from the application and does not guarantee that the
-- compiler will not be used in the future or that the compiler will actually be
-- unloaded by the implementation. Calls to 'clBuildProgram' after
-- 'clUnloadCompiler' will reload the compiler, if necessary, to build the
-- appropriate program executable.
clUnloadCompiler :: IO ()
clUnloadCompiler = raw_clUnloadCompiler >> return ()

{-| Builds (compiles and links) a program executable from the program source or
binary. OpenCL allows program executables to be built using the source or the
binary. The build options are categorized as pre-processor options, options for
math intrinsics, options that control optimization and miscellaneous
options. This specification defines a standard set of options that must be
supported by an OpenCL compiler when building program executables online or
offline. These may be extended by a set of vendor- or platform-specific options.

 * Preprocessor Options

These options control the OpenCL preprocessor which is run on each program
source before actual compilation. -D options are processed in the order they are
given in the options argument to clBuildProgram.

 [-D name] Predefine name as a macro, with definition 1.

 [-D name=definition] The contents of definition are tokenized and processed as
if they appeared during translation phase three in a `#define' directive. In
particular, the definition will be truncated by embedded newline characters.

 [-I dir] Add the directory dir to the list of directories to be searched for
header files.

 * Math Intrinsics Options

These options control compiler behavior regarding floating-point
arithmetic. These options trade off between speed and correctness.

 [-cl-single-precision-constant] Treat double precision floating-point constant
as single precision constant.

 [-cl-denorms-are-zero] This option controls how single precision and double
precision denormalized numbers are handled. If specified as a build option, the
single precision denormalized numbers may be flushed to zero and if the optional
extension for double precision is supported, double precision denormalized
numbers may also be flushed to zero. This is intended to be a performance hint
and the OpenCL compiler can choose not to flush denorms to zero if the device
supports single precision (or double precision) denormalized numbers.

This option is ignored for single precision numbers if the device does not
support single precision denormalized numbers i.e. 'CL_FP_DENORM' bit is not set
in 'clGetDeviceSingleFPConfig'.

This option is ignored for double precision numbers if the device does not
support double precision or if it does support double precison but
'CL_FP_DENORM' bit is not set in 'clGetDeviceDoubleFPConfig'.

This flag only applies for scalar and vector single precision floating-point
variables and computations on these floating-point variables inside a
program. It does not apply to reading from or writing to image objects.

 * Optimization Options

These options control various sorts of optimizations. Turning on optimization
flags makes the compiler attempt to improve the performance and/or code size at
the expense of compilation time and possibly the ability to debug the program.

 [-cl-opt-disable] This option disables all optimizations. The default is
optimizations are enabled.

 [-cl-strict-aliasing] This option allows the compiler to assume the strictest
aliasing rules.

The following options control compiler behavior regarding floating-point
arithmetic. These options trade off between performance and correctness and must
be specifically enabled. These options are not turned on by default since it can
result in incorrect output for programs which depend on an exact implementation
of IEEE 754 rules/specifications for math functions.

 [-cl-mad-enable] Allow a * b + c to be replaced by a mad. The mad computes a *
b + c with reduced accuracy. For example, some OpenCL devices implement mad as
truncate the result of a * b before adding it to c.

 [-cl-no-signed-zeros] Allow optimizations for floating-point arithmetic that
ignore the signedness of zero. IEEE 754 arithmetic specifies the behavior of
distinct +0.0 and -0.0 values, which then prohibits simplification of
expressions such as x+0.0 or 0.0*x (even with -clfinite-math only). This option
implies that the sign of a zero result isn't significant.

 [-cl-unsafe-math-optimizations] Allow optimizations for floating-point
arithmetic that (a) assume that arguments and results are valid, (b) may violate
IEEE 754 standard and (c) may violate the OpenCL numerical compliance
requirements as defined in section 7.4 for single-precision floating-point,
section 9.3.9 for double-precision floating-point, and edge case behavior in
section 7.5. This option includes the -cl-no-signed-zeros and -cl-mad-enable
options.

 [-cl-finite-math-only] Allow optimizations for floating-point arithmetic that
assume that arguments and results are not NaNs or ±∞. This option may violate
the OpenCL numerical compliance requirements defined in in section 7.4 for
single-precision floating-point, section 9.3.9 for double-precision
floating-point, and edge case behavior in section 7.5.

 [-cl-fast-relaxed-math] Sets the optimization options -cl-finite-math-only and
-cl-unsafe-math-optimizations. This allows optimizations for floating-point
arithmetic that may violate the IEEE 754 standard and the OpenCL numerical
compliance requirements defined in the specification in section 7.4 for
single-precision floating-point, section 9.3.9 for double-precision
floating-point, and edge case behavior in section 7.5. This option causes the
preprocessor macro __FAST_RELAXED_MATH__ to be defined in the OpenCL program.

 * Options to Request or Suppress Warnings

Warnings are diagnostic messages that report constructions which are not
inherently erroneous but which are risky or suggest there may have been an
error. The following languageindependent options do not enable specific warnings
but control the kinds of diagnostics produced by the OpenCL compiler.

 [-w] Inhibit all warning messages.
 
 [-Werror] Make all warnings into errors.

clBuildProgram returns the following errors when fails:

 * 'CL_INVALID_PROGRAM' if program is not a valid program object.

 * 'CL_INVALID_DEVICE' if OpenCL devices listed in device_list are not in the
list of devices associated with program.

 * 'CL_INVALID_BINARY' if program is created with
'clCreateWithProgramWithBinary' and devices listed in device_list do not have a
valid program binary loaded.

 * 'CL_INVALID_BUILD_OPTIONS' if the build options specified by options are
invalid.

 * 'CL_INVALID_OPERATION' if the build of a program executable for any of the
devices listed in device_list by a previous call to 'clBuildProgram' for program
has not completed.

 * 'CL_COMPILER_NOT_AVAILABLE' if program is created with
'clCreateProgramWithSource' and a compiler is not available
i.e. 'clGetDeviceCompilerAvailable' is set to 'False'.

 * 'CL_BUILD_PROGRAM_FAILURE' if there is a failure to build the program
executable. This error will be returned if 'clBuildProgram' does not return
until the build has completed.

 * 'CL_INVALID_OPERATION' if there are kernel objects attached to program.

 * 'CL_OUT_OF_HOST_MEMORY' if there is a failure to allocate resources required
by the OpenCL implementation on the host.  
-}
clBuildProgram :: CLProgram -> [CLDeviceID] -> String -> IO (Either CLError ())
clBuildProgram prg devs opts = allocaArray ndevs $ \pdevs -> do
  pokeArray pdevs devs
  withCString opts $ \copts -> do
    errcode <- raw_clBuildProgram prg cndevs pdevs copts nullFunPtr nullPtr
    if errcode == (fromIntegral . fromEnum $ CL_SUCCESS)
      then return $ Right ()
      else return . Left . toEnum . fromIntegral $ errcode
    where
      ndevs = length devs
      cndevs = fromIntegral ndevs

#c
enum CLProgramInfo {
  cL_PROGRAM_REFERENCE_COUNT=CL_PROGRAM_REFERENCE_COUNT,
  cL_PROGRAM_CONTEXT=CL_PROGRAM_CONTEXT,
  cL_PROGRAM_NUM_DEVICES=CL_PROGRAM_NUM_DEVICES,
  cL_PROGRAM_DEVICES=CL_PROGRAM_DEVICES,
  cL_PROGRAM_SOURCE=CL_PROGRAM_SOURCE,
  cL_PROGRAM_BINARY_SIZES=CL_PROGRAM_BINARY_SIZES,
  cL_PROGRAM_BINARIES=CL_PROGRAM_BINARIES,
  };
#endc
{#enum CLProgramInfo {upcaseFirstLetter} #}

getProgramInfoSize :: CLProgram -> CLProgramInfo_ -> IO (Either CLError CSize)
getProgramInfoSize prg infoid = alloca $ \(value_size :: Ptr CSize) -> do
  errcode <- raw_clGetProgramInfo prg infoid 0 nullPtr value_size
  if errcode == (fromIntegral . fromEnum $ CL_SUCCESS)
    then fmap Right $ peek value_size
    else return . Left . toEnum . fromIntegral $ errcode
  
-- | Return the program reference count. The reference count returned should be
-- considered immediately stale. It is unsuitable for general use in
-- applications. This feature is provided for identifying memory leaks.
clGetProgramReferenceCount :: CLProgram -> IO (Either CLError CLuint)
clGetProgramReferenceCount prg = wrapGetInfo (\(dat :: Ptr CLuint) 
                                              -> raw_clGetProgramInfo prg infoid size (castPtr dat)) id
    where 
      infoid = getCLValue CL_PROGRAM_REFERENCE_COUNT
      size = fromIntegral $ sizeOf (0::CLuint)

-- | Return the context specified when the program object is created.
clGetProgramContext :: CLProgram -> IO (Either CLError CLContext)
clGetProgramContext prg = wrapGetInfo (\(dat :: Ptr CLContext) 
                                       -> raw_clGetProgramInfo prg infoid size (castPtr dat)) id
    where 
      infoid = getCLValue CL_PROGRAM_CONTEXT
      size = fromIntegral $ sizeOf (nullPtr::CLContext)

-- | Return the number of devices associated with program.
clGetProgramNumDevices :: CLProgram -> IO (Either CLError CLuint)
clGetProgramNumDevices prg = wrapGetInfo (\(dat :: Ptr CLuint) 
                                       -> raw_clGetProgramInfo prg infoid size (castPtr dat)) id
    where 
      infoid = getCLValue CL_PROGRAM_NUM_DEVICES
      size = fromIntegral $ sizeOf (0::CLuint)

-- | Return the list of devices associated with the program object. This can be
-- the devices associated with context on which the program object has been
-- created or can be a subset of devices that are specified when a progam object
-- is created using 'clCreateProgramWithBinary'.
clGetProgramDevices :: CLProgram -> IO (Either CLError [CLDeviceID])
clGetProgramDevices prg = do
  sval <- getProgramInfoSize prg infoid
  case sval of
    Left err -> return . Left $ err
    Right size -> allocaArray (numElems size) $ \(buff :: Ptr CLDeviceID) -> do
      errcode <- raw_clGetProgramInfo prg infoid size (castPtr buff) nullPtr
      if errcode == (fromIntegral . fromEnum $ CL_SUCCESS)
        then fmap Right $ peekArray (numElems size) buff
        else return . Left . toEnum . fromIntegral $ errcode
    where 
      infoid = getCLValue CL_PROGRAM_DEVICES
      numElems s = (fromIntegral s) `div` elemSize
      elemSize = sizeOf (nullPtr::CLDeviceID)

-- | Return the program source code specified by
-- 'clCreateProgramWithSource'. The source string returned is a concatenation of
-- all source strings specified to 'clCreateProgramWithSource' with a null
-- terminator. The concatenation strips any nulls in the original source
-- strings. The actual number of characters that represents the program source
-- code including the null terminator is returned in param_value_size_ret.
clGetProgramSource :: CLProgram -> IO (Either CLError String)
clGetProgramSource prg = do
  sval <- getProgramInfoSize prg infoid
  case sval of
    Left err -> return . Left $ err
    Right n -> allocaArray (fromIntegral n) $ \(buff :: CString) -> do
      errcode <- raw_clGetProgramInfo prg infoid n (castPtr buff) nullPtr
      if errcode == (fromIntegral . fromEnum $ CL_SUCCESS)
        then fmap Right $ peekCString buff
        else return . Left . toEnum . fromIntegral $ errcode
    where 
      infoid = getCLValue CL_PROGRAM_SOURCE
  
-- | Returns an array that contains the size in bytes of the program binary for
-- each device associated with program. The size of the array is the number of
-- devices associated with program. If a binary is not available for a
-- device(s), a size of zero is returned.
clGetProgramBinarySizes :: CLProgram -> IO (Either CLError [CSize])
clGetProgramBinarySizes prg = do
  sval <- getProgramInfoSize prg infoid
  case sval of
    Left err -> return . Left $ err
    Right size -> allocaArray (numElems size) $ \(buff :: Ptr CSize) -> do
      errcode <- raw_clGetProgramInfo prg infoid size (castPtr buff) nullPtr
      if errcode == (fromIntegral . fromEnum $ CL_SUCCESS)
        then fmap Right $ peekArray (numElems size) buff
        else return . Left . toEnum . fromIntegral $ errcode
    where 
      infoid = getCLValue CL_PROGRAM_BINARY_SIZES
      numElems s = (fromIntegral s) `div` elemSize
      elemSize = sizeOf (0::CSize)

{-| Return the program binaries for all devices associated with program. For
each device in program, the binary returned can be the binary specified for the
device when program is created with 'clCreateProgramWithBinary' or it can be the
executable binary generated by 'clBuildProgram'. If program is created with
'clCreateProgramWithSource', the binary returned is the binary generated by
'clBuildProgram'. The bits returned can be an implementation-specific
intermediate representation (a.k.a. IR) or device specific executable bits or
both. The decision on which information is returned in the binary is up to the
OpenCL implementation.

To find out which device the program binary in the array refers to, use the
'clGetProgramDevices' query to get the list of devices. There is a one-to-one
correspondence between the array of data returned by 'clGetProgramBinaries' and
array of devices returned by 'clGetProgramDevices'.  
-}
--clGetProgramBinaries :: CLProgram -> IO (Either CLError [[Word8]])
clGetProgramBinaries prg = do
  sval <- getProgramInfoSize prg infoid
  case sval of
    Left err -> return . Left $ err
    Right size -> allocaArray (numElems size) $ \(buff :: Ptr (Ptr Word8)) -> do
      print sval
      print buff
      return . Left $ CL_SUCCESS
    where 
      infoid = getCLValue CL_PROGRAM_BINARIES
      numElems s = (fromIntegral s) `div` elemSize
      elemSize = sizeOf (nullPtr::Ptr Word8)
{-
CL_PROGRAM_BINARIES	Return type: unsigned char *[]
Return the program binaries for all devices associated with program. For each device in program, the binary returned can be the binary specified for the device when program is created with clCreateProgramWithBinary or it can be the executable binary generated by clBuildProgram. If program is created with clCreateProgramWithSource, the binary returned is the binary generated by clBuildProgram. The bits returned can be an implementation-specific intermediate representation (a.k.a. IR) or device specific executable bits or both. The decision on which information is returned in the binary is up to the OpenCL implementation.

param_value points to an array of n pointers where n is the number of devices associated with program. The buffer sizes needed to allocate the memory that these n pointers refer to can be queried using the CL_PROGRAM_BINARY_SIZES query as described in this table.

Each entry in this array is used by the implementation as the location in memory where to copy the program binary for a specific device, if there is a binary available. To find out which device the program binary in the array refers to, use the CL_PROGRAM_DEVICES query to get the list of devices. There is a one-to-one correspondence between the array of n pointers returned by CL_PROGRAM_BINARIES and array of devices returned by CL_PROGRAM_DEVICES.
-}

-- -----------------------------------------------------------------------------
#c
enum CLProgramBuildInfo {
  cL_PROGRAM_BUILD_STATUS=CL_PROGRAM_BUILD_STATUS,
  cL_PROGRAM_BUILD_OPTIONS=CL_PROGRAM_BUILD_OPTIONS,
  cL_PROGRAM_BUILD_LOG=CL_PROGRAM_BUILD_LOG,
  };
#endc
{#enum CLProgramBuildInfo {upcaseFirstLetter} #}

getProgramBuildInfoSize :: CLProgram -> CLDeviceID -> CLProgramInfo_ -> IO (Either CLError CSize)
getProgramBuildInfoSize prg device infoid = alloca $ \(value_size :: Ptr CSize) -> do
  errcode <- raw_clGetProgramBuildInfo prg device infoid 0 nullPtr value_size
  if errcode == (fromIntegral . fromEnum $ CL_SUCCESS)
    then fmap Right $ peek value_size
    else return . Left . toEnum . fromIntegral $ errcode
  
-- | Returns the build status of program for a specific device as given by
-- device.
clGetProgramBuildStatus :: CLProgram -> CLDeviceID -> IO (Either CLError CLBuildStatus)
clGetProgramBuildStatus prg device = wrapGetInfo (\(dat :: Ptr CLBuildStatus_) 
                                           -> raw_clGetProgramBuildInfo prg device infoid size (castPtr dat)) getEnumCL
    where 
      infoid = getCLValue CL_PROGRAM_BUILD_STATUS
      size = fromIntegral $ sizeOf (0::CLBuildStatus_)

-- | Return the build options specified by the options argument in
-- clBuildProgram for device. If build status of program for device is
-- 'CL_BUILD_NONE', an empty string is returned.
clGetProgramBuildOptions :: CLProgram -> CLDeviceID -> IO (Either CLError String)
clGetProgramBuildOptions prg device = do
  sval <- getProgramBuildInfoSize prg device infoid
  case sval of
    Left err -> return . Left $ err
    Right n -> allocaArray (fromIntegral n) $ \(buff :: CString) -> do
      errcode <- raw_clGetProgramBuildInfo prg device infoid n (castPtr buff) nullPtr
      if errcode == (fromIntegral . fromEnum $ CL_SUCCESS)
        then fmap Right $ peekCString buff
        else return . Left . toEnum . fromIntegral $ errcode
    where 
      infoid = getCLValue CL_PROGRAM_BUILD_OPTIONS
  
-- | Return the build log when 'clBuildProgram' was called for device. If build
-- status of program for device is 'CL_BUILD_NONE', an empty string is returned.
clGetProgramBuildLog :: CLProgram -> CLDeviceID -> IO (Either CLError String)
clGetProgramBuildLog prg device = do
  sval <- getProgramBuildInfoSize prg device infoid
  case sval of
    Left err -> return . Left $ err
    Right n -> allocaArray (fromIntegral n) $ \(buff :: CString) -> do
      errcode <- raw_clGetProgramBuildInfo prg device infoid n (castPtr buff) nullPtr
      if errcode == (fromIntegral . fromEnum $ CL_SUCCESS)
        then fmap Right $ peekCString buff
        else return . Left . toEnum . fromIntegral $ errcode
    where 
      infoid = getCLValue CL_PROGRAM_BUILD_LOG
  
-- -----------------------------------------------------------------------------
