<*
 @require types::is_int($Typeof(SIZE)) : "Size must is a integer"
 @require SIZE > 0 : "Size must be bigger than 0"
*>
module simple_player::ringbuffer <Type, SIZE>;
import std::atomic::types, std::math;


struct RingBuffer
{
	Type[SIZE] buffer;
	Atomic{usz} head @align(64);
	Atomic{usz} tail @align(64);
}

fn void RingBuffer.init(&self) @inline
{
	*self = { };
}

fn bool RingBuffer.push(&self, Type element)
{
	usz h = self.head.load(mem::AtomicOrdering.ACQUIRE);
	usz t = self.tail.load(mem::AtomicOrdering.RELAXED);
	if (t - h >= SIZE) return false;

	self.buffer[t & (SIZE - 1)] = element;
	self.tail.add(1, mem::AtomicOrdering.RELEASE);

	return true;
}

fn usz RingBuffer.push_all(&self, Type[] elements)
{
	foreach (index, element : elements) if (!self.push(element)) return (usz)index;
	return elements.len;
}

faultdef NO_SUCH_ELEMENT;

fn Type? RingBuffer.pop(&self)
{
	usz h = self.head.load(mem::AtomicOrdering.RELAXED);
	usz t = self.tail.load(mem::AtomicOrdering.ACQUIRE);

	if (h >= t) return NO_SUCH_ELEMENT~;

	Type item = self.buffer[h & (SIZE - 1)];
	self.head.add(1, mem::AtomicOrdering.RELEASE);

	return item;
}

fn Type[]? RingBuffer.pop_into(&self, Type[] target)
{
	if (self.is_empty()) return target[:0];

	sz len = min(target.len, self.free_size());
	for (sz i = 0; i < len; i++) target[i] = self.pop()!;

	return target[:len];
}

fn bool RingBuffer.is_empty(
	&self
) @inline => self.head.load(mem::AtomicOrdering.ACQUIRE) >= self.tail.load(mem::AtomicOrdering.ACQUIRE);

fn bool RingBuffer.is_full(
	&self
) @inline => self.tail.load(mem::AtomicOrdering.ACQUIRE) - self.head.load(mem::AtomicOrdering.ACQUIRE) >= SIZE;

fn usz RingBuffer.len(&self) @operator(len) => SIZE;

fn sz RingBuffer.free_size(
	&self
) => SIZE - (sz)(self.tail.load(mem::AtomicOrdering.ACQUIRE) - self.head.load(mem::AtomicOrdering.ACQUIRE));

fn void RingBuffer.clear(&self) @inline
{
	self.head.store(0, mem::AtomicOrdering.RELEASE);
	self.tail.store(0, mem::AtomicOrdering.RELEASE);
}
